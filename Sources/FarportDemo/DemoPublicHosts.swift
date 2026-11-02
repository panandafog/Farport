#if DEBUG
import FarportCore
import Foundation

extension DemoCatalog {
    static var sftpOnlyHostID: UUID { identifier(32) }
    /// Published shared accounts, not private credentials. Never included in Release.
    public static var publicHosts: [SavedHost] {
        [
            SavedHost(profile: HostProfile(id: identifier(30), name: "Public · Bandit SSH",
                hostname: "bandit.labs.overthewire.org", port: 2220, username: "bandit0",
                notes: "Live Linux SSH learning server. Standard SSH; no tmux required. " +
                    "https://overthewire.org/wargames/bandit/bandit0.html"),
                credentials: HostCredentials(password: "bandit0")),
            SavedHost(profile: HostProfile(id: identifier(31), name: "Public · Rebex SSH / SFTP",
                hostname: "test.rebex.net", username: "demo",
                notes: "Live read-only SSH/SFTP test server with a limited shell, not Linux/tmux. " +
                    "https://www.rebex.net/buru-sftp-server/demo/"),
                credentials: HostCredentials(password: "password")),
            SavedHost(profile: HostProfile(id: sftpOnlyHostID, name: "Public · Wing SFTP (Mac)",
                hostname: "demo.wftpserver.com", port: 2222, username: "demo",
                notes: "Live read-only SFTP server. Open Files on macOS; no interactive terminal. " +
                    "https://www.wftpserver.com/onlinedemo.htm"),
                credentials: HostCredentials(password: "demo"))
        ]
    }
}
#endif
