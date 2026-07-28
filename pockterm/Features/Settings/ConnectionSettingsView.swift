import SwiftUI
import SwiftData

/// App-wide default for how long idle sessions stay connected. Hosts and
/// groups can override this; hosts with no override inherit it.
struct ConnectionSettingsView: View {
    @Environment(\.modelContext) private var ctx
    @State private var seconds = 0

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
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { seconds = ConnectionSettings.single(in: ctx).defaultKeepAliveSeconds }
        .onChange(of: seconds) { _, new in
            ConnectionSettings.single(in: ctx).defaultKeepAliveSeconds = new
            try? ctx.save()
        }
    }
}
