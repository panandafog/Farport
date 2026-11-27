import AppIntents

struct FarportAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RunSSHCommandIntent(), phrases: [
            "Run a server command with \(.applicationName)"
        ], shortTitle: LocalizedStringResource("Run SSH Command", table: "AppIntents"), systemImageName: "terminal")
        AppShortcut(intent: FindSSHHostsIntent(), phrases: [
            "Find servers in \(.applicationName)"
        ], shortTitle: LocalizedStringResource("Find Saved Hosts", table: "AppIntents"), systemImageName: "server.rack")
        AppShortcut(intent: OpenSSHHostSettingsIntent(), phrases: [
            "Open server settings in \(.applicationName)"
        ], shortTitle: LocalizedStringResource("Open Host Settings", table: "AppIntents"),
                    systemImageName: "slider.horizontal.3")
    }
}
