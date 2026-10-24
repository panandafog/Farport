import FarportCore
import FarportLocalization
import Foundation
import NIO

enum TCPConnectionFailure {
    static func mayBeLocalNetworkDenied(_ error: Error) -> Bool {
        if let error = error as? IOError { return error.errnoCode == EHOSTUNREACH }
        return (error as? NIOConnectionError)?.connectionErrors.contains {
            ($0.error as? IOError)?.errnoCode == EHOSTUNREACH
        } == true
    }

    static func translate(_ error: Error) -> TerminalConnectionError? {
        if let error = error as? NIOConnectionError { return connection(error) }
        if let error = error as? IOError { return io(error) }
        return nil
    }

    private static func connection(_ error: NIOConnectionError) -> TerminalConnectionError {
        let target = "\(error.host):\(error.port)"
        let attempts = error.connectionErrors.prefix(4).map { failure in
            "\(failure.target): \(detail(failure.error))"
        }
        if !attempts.isEmpty {
            let message = L10n.text("Could not connect to %@. %@", target, attempts.joined(separator: "; "))
            let denied = error.connectionErrors.allSatisfy { failure in
                (failure.error as? IOError).map { permissionDenied($0.errnoCode) } == true
            }
            if denied { return .configuration(message + " " + accessHint) }
            let unreachable = error.connectionErrors.contains { failure in
                (failure.error as? IOError)?.errnoCode == EHOSTUNREACH
            }
            return .transport(message + (unreachable ? " " + reachabilityHint : ""))
        }
        let dns = [error.dnsAError, error.dnsAAAAError].compactMap { $0 }.map(detail)
        let message = dns.isEmpty ? String(describing: error) :
            L10n.text("DNS lookup failed: %@", dns.joined(separator: "; "))
        return .transport(L10n.text("Could not resolve or connect to %@. %@", target, message))
    }

    private static func io(_ error: IOError) -> TerminalConnectionError {
        let message = detail(error)
        return permissionDenied(error.errnoCode) ? .configuration(message + " " + accessHint) : .transport(message)
    }

    private static func detail(_ error: Error) -> String {
        // NIO errors expose the actual POSIX/DNS failure through description, not Foundation's generic NSError text.
        if let error = error as? IOError { return error.description }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private static func permissionDenied(_ code: CInt) -> Bool { code == EACCES || code == EPERM }

    private static var accessHint: String {
        #if os(macOS)
        L10n.text(
            "Network access was denied. For a local server, allow Farport in System Settings > " +
            "Privacy & Security > Local Network, then connect again. Also check firewall or VPN rules."
        )
        #else
        L10n.text(
            "Network access was denied. For a local server, allow Farport in Settings > Privacy & " +
            "Security > Local Network, then connect again. Also check firewall or VPN rules."
        )
        #endif
    }

    private static var reachabilityHint: String {
        L10n.text(
            "Check the server address, network and VPN. For a local server, also check Farport's " +
            "Local Network permission."
        )
    }
}
