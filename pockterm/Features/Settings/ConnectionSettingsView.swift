import SwiftUI
import SwiftData

/// App-wide default for how long idle sessions stay connected. Hosts and
/// groups can override this; hosts with no override inherit it.
struct ConnectionSettingsView: View {
    @Environment(\.modelContext) private var ctx
    @State private var seconds = 0
    @State private var autoReconnect = true
    @State private var tmuxAttach = false

    var body: some View {
        Form {
            Section {
                Picker("Hold time", selection: $seconds) {
                    ForEach(KeepAlive.options) { opt in
                        Text(opt.label).tag(opt.seconds)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Keep sessions alive when idle")
            } footer: {
                Text("The default for all hosts. \"Off\" keeps the current behavior. Individual hosts and groups can override this.")
            }
            Section {
                Toggle("Reconnect Automatically", isOn: $autoReconnect)
                Toggle("Reopen in tmux", isOn: $tmuxAttach)
            } header: {
                Text("Reconnect")
            } footer: {
                Text("When the connection drops, Pockterm reconnects and reopens the shell on its own. Reopen in tmux starts every session inside the tmux session \"pockterm\", so a reconnect lands you back where you were. Individual hosts and groups can override these.")
            }
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let settings = ConnectionSettings.single(in: ctx)
            seconds = settings.defaultKeepAliveSeconds
            autoReconnect = settings.autoReconnect
            tmuxAttach = settings.tmuxAttach
        }
        .onChange(of: autoReconnect) { _, new in
            ConnectionSettings.single(in: ctx).autoReconnect = new
            try? ctx.save()
        }
        .onChange(of: tmuxAttach) { _, new in
            ConnectionSettings.single(in: ctx).tmuxAttach = new
            try? ctx.save()
        }
        .onChange(of: seconds) { _, new in
            ConnectionSettings.single(in: ctx).defaultKeepAliveSeconds = new
            try? ctx.save()
        }
    }
}
