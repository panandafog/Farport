import AppIntents
import FarportCore
import Foundation

struct ShortcutHost: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Saved Host", table: "AppIntents")
    )
    static let defaultQuery = ShortcutHostQuery()
    let id: UUID
    @Property(title: LocalizedStringResource("Name", table: "AppIntents")) var name: String
    @Property(title: LocalizedStringResource("Hostname", table: "AppIntents")) var hostname: String
    @Property(title: LocalizedStringResource("Username", table: "AppIntents")) var username: String
    @Property(title: LocalizedStringResource("Port", table: "AppIntents")) var port: Int

    init(_ profile: HostProfile) {
        id = profile.id; name = profile.displayName; hostname = profile.hostname
        username = profile.username; port = profile.port
    }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(username)@\(hostname):\(port)")
    }
}

struct ShortcutHostQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ShortcutHost] {
        let profiles = try ShortcutServices.library().automationProfiles()
        let indexed = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        return identifiers.compactMap { indexed[$0].map(ShortcutHost.init) }
    }
    func suggestedEntities() async throws -> [ShortcutHost] {
        try ShortcutServices.library().automationProfiles().map(ShortcutHost.init)
    }
    func entities(matching string: String) async throws -> [ShortcutHost] {
        try ShortcutServices.library().automationProfiles().filter {
            string.isEmpty || ($0.displayName + " " + $0.address).localizedCaseInsensitiveContains(string)
        }.map(ShortcutHost.init)
    }
}
