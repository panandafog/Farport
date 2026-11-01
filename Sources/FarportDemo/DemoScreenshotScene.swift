#if DEBUG
import Foundation

public enum DemoScreenshotScene: String, CaseIterable, Sendable {
    case hosts, terminal, logs, files
    case hostSettings = "host-settings"

    public static let argumentPrefix = "--screenshot-scene="

    public static func requested(in arguments: [String]) -> Self? {
        arguments.first { $0.hasPrefix(argumentPrefix) }.flatMap {
            Self(rawValue: String($0.dropFirst(argumentPrefix.count)))
        }
    }

    public static func isRequested(in arguments: [String]) -> Bool {
        arguments.contains { $0.hasPrefix(argumentPrefix) }
    }
}
#endif
