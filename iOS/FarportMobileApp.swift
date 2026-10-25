import FarportLocalization
import FarportSessions
import SwiftUI
import UIKit

@main
struct FarportMobileApp: App {
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            MobileAppRoot(loadLibrary: MobileLibraryModel.makeApplication) { delegate.model = $0 }
        }
    }
}

final class MobileAppDelegate: NSObject, UIApplicationDelegate {
    weak var model: HostLibraryModel<MobileTerminalModel>?

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        model?.cloud?.refresh()
        completionHandler(.noData)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        model?.cloud?.error = L10n.text("iCloud push updates are unavailable. Sync Now still works. %@",
                                       error.localizedDescription)
    }
}
