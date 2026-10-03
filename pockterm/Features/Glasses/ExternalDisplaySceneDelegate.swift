import SwiftUI
import UIKit

/// Owns the window iOS gives the app on an external display. It registers
/// with `ExternalDisplay` while connected and shows `GlassesRootView`.
@MainActor
final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let container = AppContainer.shared
        let id = ObjectIdentifier(windowScene)
        let host = UIHostingController(rootView: GlassesRootView(
            manager: container.sessions, display: container.display, sceneID: id))
        host.view.backgroundColor = .black
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        container.display.attach(id)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        AppContainer.shared.display.detach(ObjectIdentifier(scene))
        window = nil
    }
}
