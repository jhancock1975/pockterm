import SwiftUI

/// What a session shows when it isn't simply connected: connecting, failed,
/// closed, or dropped for inactivity. It sits over the terminal on the phone
/// and on the glasses, and replaces the file browser in glasses mode.
struct SessionStatusView: View {
    let session: TerminalSession
    let manager: SessionManager

    var body: some View {
        switch session.status {
        case .connecting:
            ProgressView("Connecting…").controlSize(.large).tint(.white)
        case .failed(let message):
            ContentUnavailableView("Connection Failed", systemImage: "xmark.octagon",
                                   description: Text(message))
                .foregroundStyle(.white)
        case .closed:
            ContentUnavailableView("Session Closed", systemImage: "bolt.horizontal",
                                   description: Text("The remote shell ended."))
                .foregroundStyle(.white)
        case .idleDisconnected:
            ContentUnavailableView {
                Label("Disconnected due to inactivity", systemImage: "moon.zzz")
            } description: {
                Text("This session was closed after being idle. You can change how long sessions stay connected.")
            } actions: {
                Button("Change how long sessions stay connected") {
                    manager.requestOpenConnectionSettings = true
                    manager.minimize()   // dismiss the full-screen terminal cover
                }
            }
            .foregroundStyle(.white)
        case .connected:
            EmptyView()
        }
    }
}
