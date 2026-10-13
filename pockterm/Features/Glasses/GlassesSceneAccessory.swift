import SwiftUI
import UIKit

/// Offers the glasses scene to iOS 27 and later.
///
/// Apps built with the iOS 27 SDK no longer get a
/// `windowExternalDisplayNonInteractive` scene from the Info.plist scene
/// manifest. iOS connects one only after a view controller registers a scene
/// accessory, and only while that view controller is presented. Without this
/// the glasses just mirror the phone. iOS 26 and earlier still take the scene
/// from the Info.plist entry. Both paths end in `ExternalDisplaySceneDelegate`.
///
/// Sits behind the root view, so the registration lasts as long as the app's
/// window, the terminal's full-screen cover included.
struct GlassesSceneAccessory: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Registrar() }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    private final class Registrar: UIViewController {
        /// A `UISceneAccessoryRegistration`, which only exists on iOS 27.
        private var registration: AnyObject?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            guard #available(iOS 27, *) else { return }
            let configuration = UISceneConfiguration(
                name: "External Display", sessionRole: .windowExternalDisplayNonInteractive)
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
            registration = registerSceneAccessory(.externalNonInteractive(sceneConfiguration: configuration))
        }
    }
}
