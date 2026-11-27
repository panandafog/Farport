import AppIntents
import FarportCore
import FarportLocalization

struct OpenSSHHostSettingsIntent: AppIntent {
    static let title = LocalizedStringResource("Open Host Settings", table: "AppIntents")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @available(macOS 26, iOS 26, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: LocalizedStringResource("Host", table: "AppIntents")) var host: ShortcutHost

    static var parameterSummary: some ParameterSummary {
        Summary("Open settings for \(\.$host)", table: "AppIntents")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard try ShortcutServices.library().automationProfiles().contains(where: { $0.id == host.id }) else {
            throw HarborError.message(L10n.text("This saved host no longer exists. Select another host in Shortcuts."))
        }
        ShortcutHostNavigation.shared.pendingHostID = host.id
        return .result()
    }
}
