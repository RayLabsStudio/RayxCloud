// OrientationLock.swift
// iOS only. The library rotates freely; opening a stream locks the app to
// landscape and rotates the device into it, closing the stream unlocks it.
//

#if os(iOS)
import UIKit

final class RayxCloudAppDelegate: NSObject, UIApplicationDelegate {
    @MainActor static var supportedOrientations: UIInterfaceOrientationMask = .all

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.supportedOrientations
    }
}

enum OrientationLock {
    @MainActor
    static func set(_ mask: UIInterfaceOrientationMask) {
        RayxCloudAppDelegate.supportedOrientations = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                print("[Orientation] geometry update failed: \(error)")
            }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
#endif
