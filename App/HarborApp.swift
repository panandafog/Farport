import HarborCore
import SwiftUI

@main
struct HarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = LibraryModel()

    var body: some Scene {
        WindowGroup {
            LibraryView(model: model)
                .frame(minWidth: 860, minHeight: 560)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandMenu("iCloud") {
                Button("Host Sync") { model.cloud?.showingSettings = true }.disabled(model.cloud == nil)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Host") { model.editor = SavedHost() }
                    .keyboardShortcut("n")
                Button("New Terminal Tab") { model.selectedWorkspace?.addTerminal() }
                    .keyboardShortcut("t").disabled(model.selectedWorkspace == nil)
            }
            CommandMenu("Terminal") {
                Button("Next Tab") { model.selectedWorkspace?.selectNextTerminal(offset: 1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { model.selectedWorkspace?.selectNextTerminal(offset: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
            }
            CommandMenu("Security") {
                Button("Server Keys") { model.trust?.showKeys(hosts: model.hosts) }.disabled(model.trust == nil)
            }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: LibraryModel?
    private var lifecycleObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NSWorkspace.shared.notificationCenter
        lifecycleObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.model?.systemWillSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.model?.systemDidWake() }
            }
        ]
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidBecomeActive(_ notification: Notification) { model?.cloud?.refresh() }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        model?.cloud?.refresh()
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        model?.cloud?.error = "iCloud push updates are unavailable. Sync Now still works. " + error.localizedDescription
    }

    func applicationWillTerminate(_ notification: Notification) {
        lifecycleObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        model?.closeAll()
    }
}
