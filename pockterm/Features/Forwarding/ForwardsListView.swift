import SwiftUI
import SwiftData

struct ForwardsListView: View {
    @Bindable var runner: ForwardRunner
    @Environment(\.modelContext) private var ctx
    @Query(sort: \PortForward.label) private var forwards: [PortForward]
    @State private var editing: PortForward?

    var body: some View {
        NavigationStack {
            Group {
                if forwards.isEmpty {
                    ContentUnavailableView("No Port Forwards", systemImage: "arrow.left.arrow.right",
                                           description: Text("Tap + to add a tunnel."))
                } else {
                    List {
                        ForEach(forwards) { forward in
                            row(forward)
                                .swipeActions {
                                    Button("Edit") { editing = forward }.tint(.blue)
                                    Button("Delete", role: .destructive) {
                                        runner.stop(forward); ctx.delete(forward)
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Port Forwarding")
            .toolbar {
                Button {
                    editing = PortForward(label: "", type: .local, bindPort: 8080)
                } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { forward in
                ForwardEditorView(forward: forward)
            }
            .alert("Verify Host Key", isPresented: hostKeyPresented,
                   presenting: runner.pendingHostKey) { pending in
                Button(pending.storedFingerprint == nil ? "Accept" : "Accept Changed Key",
                       role: pending.storedFingerprint == nil ? nil : .destructive) {
                    pending.resume(true); runner.pendingHostKey = nil
                }
                Button("Reject", role: .cancel) { pending.resume(false); runner.pendingHostKey = nil }
            } message: { pending in
                Text(pending.info.fingerprint ?? "Fingerprint unavailable")
            }
        }
    }

    private func row(_ forward: PortForward) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(forward.label).font(.headline)
                Text(detail(forward)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                statusLabel(forward)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editing = forward }

            Button {
                runner.toggle(forward)
            } label: {
                Image(systemName: runner.isRunning(forward) ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(runner.isRunning(forward) ? .red : .green)
            }
            .buttonStyle(.plain)
        }
    }

    private func detail(_ forward: PortForward) -> String {
        switch forward.type {
        case .local:   return "L  :\(forward.bindPort) → \(forward.remoteHost):\(forward.remotePort)"
        case .remote:  return "R  server:\(forward.bindPort) → \(forward.remoteHost):\(forward.remotePort)"
        case .dynamic: return "D  SOCKS5 :\(forward.bindPort)"
        }
    }

    @ViewBuilder
    private func statusLabel(_ forward: PortForward) -> some View {
        switch runner.status(for: forward) {
        case .stopped:
            Text("Stopped").font(.caption2).foregroundStyle(.tertiary)
        case .connecting:
            Label("Connecting…", systemImage: "circle.dotted").font(.caption2).foregroundStyle(.yellow)
        case .active(let port):
            Label("Active on :\(port)", systemImage: "circle.fill").font(.caption2).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.red)
        }
    }

    private var hostKeyPresented: Binding<Bool> {
        Binding(get: { runner.pendingHostKey != nil },
                set: { if !$0, let pending = runner.pendingHostKey { pending.resume(false); runner.pendingHostKey = nil } })
    }
}
