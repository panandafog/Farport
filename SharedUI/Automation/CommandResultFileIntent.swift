import AppIntents
import Foundation
import UniformTypeIdentifiers

enum CommandResultFormat: String, AppEnum {
    case text, json
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Result Format", table: "AppIntents")
    )
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .text: DisplayRepresentation(title: LocalizedStringResource("Plain Text", table: "AppIntents")),
        .json: "JSON"
    ]
}

struct CommandResultFileIntent: AppIntent {
    static let title = LocalizedStringResource("Make Command Result File", table: "AppIntents")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: LocalizedStringResource("Command Result", table: "AppIntents")) var result: SSHCommandResultEntity
    @Parameter(title: LocalizedStringResource("Format", table: "AppIntents"), default: .text)
    var format: CommandResultFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Make \(\.$format) file from \(\.$result)", table: "AppIntents")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let data = try format == .json ? result.result.jsonData() : Data(result.result.reportText.utf8)
        return .result(value: IntentFile(data: data, filename: "Farport-command-result." +
                                        (format == .json ? "json" : "txt"),
                                        type: format == .json ? .json : .plainText))
    }
}
