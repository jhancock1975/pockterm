import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The assistant chat for the active terminal session: streaming transcript,
/// attachment chips, and Insert/Run actions on suggested commands.
struct AssistantView: View {
    @Bindable var model: AssistantModel
    let host: Host
    let secretStore: SecretStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var prompt = ""
    @State private var importingLocalFile = false
    @State private var pickingRemoteFile = false
    @State private var attachmentError: String?
    @FocusState private var promptFocused: Bool
    @State private var keyboardTop: CGFloat = .infinity
    @State private var containerBottom: CGFloat = 0

    private var keyboardOverlap: CGFloat { max(0, containerBottom - keyboardTop) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                if !model.attachments.isEmpty { attachmentChips }
                if let error = model.errorMessage {
                    Text(error)
                        .font(.footnote).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal).padding(.top, 6)
                }
                if let pending = model.pendingApproval {
                    approvalCard(pending)
                }
                inputBar
                    .padding(.bottom, keyboardOverlap)
                    .animation(.easeOut(duration: 0.2), value: keyboardOverlap)
            }
            .background(keyboardOverlapReader)
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) { attachMenu }
                // Conversations persist per host now, so there has to be a way
                // to get rid of one: a transcript holds terminal output and
                // tool results, which is exactly what a user may not want kept.
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        model.clearConversation()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Clear Conversation")
                    .disabled(model.messages.isEmpty || model.isStreaming)
                }
                // The same chip AISettingsView and HostEditorView carry. The
                // assistant needed it most and was the one screen without it:
                // the keyboard opens automatically with the sheet, and until
                // it is dismissed it hides most of the answer.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { promptFocused = false } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Dismiss Keyboard")
                }
            }
        }
        // Keyboard avoidance is done manually (`keyboardOverlapReader` +
        // `inputBar` padding): SwiftUI's automatic avoidance uses a keyboard
        // frame that excludes the predictive bar, leaving the input bar
        // behind it (same OS defect TerminalHostView works around). Must be
        // on the sheet root — inside the NavigationStack it can't undo the
        // inset applied out here.
        .ignoresSafeArea(.keyboard)
        .fileImporter(isPresented: $importingLocalFile,
                      allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            importLocalFile(result)
        }
        .sheet(isPresented: $pickingRemoteFile) {
            RemoteFilePickerView(host: host, secretStore: secretStore,
                                 modelContext: modelContext) { name, data in
                model.addAttachment(name: name, data: data)
            }
        }
        .alert("Couldn't Attach File", isPresented: attachmentErrorPresented) {
            Button("OK") { attachmentError = nil }
        } message: {
            Text(attachmentError ?? "")
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty { emptyState }
                    ForEach(model.messages) { message in
                        Group {
                            if message.role == .tool {
                                ToolCard(message: message)
                            } else {
                                MessageBubble(message: message,
                                              onInsert: { insertAndDismiss($0, run: false) },
                                              onRun: { insertAndDismiss($0, run: true) })
                            }
                        }
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: model.messages.last?.text) {
                if let last = model.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask about what's on screen, or ask for a command.")
                .font(.callout)
            Text("The terminal output\(model.attachments.isEmpty ? "" : " and attached files") will be sent to \(model.settings.activeProvider.displayName).")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.attachments) { attachment in
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text").font(.caption)
                        Text(attachment.name).font(.caption).lineLimit(1)
                        Button {
                            model.removeAttachment(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption)
                        }
                        .accessibilityLabel("Remove \(attachment.name)")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 6)
    }

    private var attachMenu: some View {
        Menu {
            Button { importingLocalFile = true } label: {
                Label("Attach Local File", systemImage: "iphone")
            }
            Button { pickingRemoteFile = true } label: {
                Label("Attach Remote File", systemImage: "server.rack")
            }
        } label: {
            Image(systemName: "paperclip")
        }
        .accessibilityLabel("Attach a file")
    }

    /// Tracks how far the keyboard overlaps the bottom of the chat column so
    /// `inputBar` can pad itself clear of it. Keyboard top and container
    /// bottom move independently (the notification can fire while the sheet
    /// is still animating in), so both are tracked and the overlap recomputed
    /// on either change.
    private var keyboardOverlapReader: some View {
        GeometryReader { geo in
            let bottom = geo.frame(in: .global).maxY
            Color.clear
                .onAppear { containerBottom = bottom }
                .onChange(of: bottom) { containerBottom = bottom }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                    guard let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                                     as? NSValue)?.cgRectValue else { return }
                    keyboardTop = end.minY
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillHideNotification)) { _ in
                    keyboardTop = .infinity
                }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask the assistant…", text: $prompt, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($promptFocused)
                .onSubmit(send)
                .onAppear { promptFocused = true }
            if model.isStreaming {
                Button { model.stop() } label: {
                    Image(systemName: "stop.circle.fill").font(.title2)
                }
                .accessibilityLabel("Stop generating")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding()
    }

    private func approvalCard(_ pending: PendingToolApproval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The assistant wants to run:", systemImage: "exclamationmark.shield")
                .font(.caption.bold())
            Text("\(pending.call.name): \(AssistantModel.summary(of: pending.call))")
                .font(.system(.caption, design: .monospaced))
                .lineLimit(6)
            HStack {
                Button("Deny", role: .destructive) { model.resolveApproval(false) }
                Spacer()
                Button("Run") { model.resolveApproval(true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func send() {
        model.send(prompt)
        prompt = ""
    }

    /// Inserting or running a command dismisses the sheet so the terminal is
    /// visible while the command types (and, for Run, executes).
    private func insertAndDismiss(_ command: String, run: Bool) {
        if run { model.runCommand(command) } else { model.insertCommand(command) }
        dismiss()
    }

    private func importLocalFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            model.addAttachment(name: url.lastPathComponent, data: try Data(contentsOf: url))
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private var attachmentErrorPresented: Binding<Bool> {
        Binding(get: { attachmentError != nil },
                set: { if !$0 { attachmentError = nil } })
    }
}

/// A transcript card for one tool invocation: what ran, its (truncated)
/// output, or that it was denied.
private struct ToolCard: View {
    let message: AssistantMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(message.toolName ?? "tool",
                  systemImage: message.denied ? "hand.raised" : "wrench.and.screwdriver")
                .font(.caption.bold())
            if let detail = message.toolDetail, !detail.isEmpty {
                Text(detail).font(.system(.caption, design: .monospaced))
            }
            if message.denied {
                Text("Denied").font(.caption2).foregroundStyle(.red)
            } else if let result = message.toolResult {
                Text(result.prefix(400))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// One transcript bubble; assistant replies get Insert/Run chips for each
/// fenced command.
private struct MessageBubble: View {
    let message: AssistantMessage
    let onInsert: (String) -> Void
    let onRun: (String) -> Void

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            Text(message.text.isEmpty ? "…" : message.text)
                .textSelection(.enabled)
                .padding(10)
                .background(message.role == .user ? Color.accentColor.opacity(0.2)
                                                  : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            ForEach(Array(message.commands.enumerated()), id: \.offset) { _, command in
                commandChip(command)
            }
        }
        .frame(maxWidth: .infinity,
               alignment: message.role == .user ? .trailing : .leading)
    }

    private func commandChip(_ command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(4)
            HStack(spacing: 12) {
                Button { onRun(command) } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button { onInsert(command) } label: {
                    Label("Insert", systemImage: "text.cursor")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1))
    }
}
