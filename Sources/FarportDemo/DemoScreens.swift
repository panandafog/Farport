#if DEBUG
// These are fictional remote-machine transcripts, not application UI strings.
enum DemoScreens {
    static let responses: [String: String] = [
        "": "",
        "help": "Sample commands: help, ls, ls -la, pwd, cd src, cd .., cat README.md,\r\n" +
            "git status, docker ps, logs, uptime, uname -a, clear, exit\r\n",
        "cat README.md": "# Atlas API\r\n\r\nA small service for a connected world.\r\n" +
            "All services are healthy. Ready to deploy.\r\n",
        "git status": "On branch main\r\nYour branch is up to date with 'origin/main'.\r\n\r\n" +
            "\u{1b}[32mworking tree clean\u{1b}[0m\r\n",
        "docker ps": "\u{1b}[1mNAME          STATUS              PORTS\u{1b}[0m\r\n" +
            "atlas-api     \u{1b}[32mUp 12 days\u{1b}[0m          8080/tcp\r\n" +
            "postgres      \u{1b}[32mUp 12 days\u{1b}[0m          5432/tcp\r\n" +
            "redis         \u{1b}[32mUp 12 days\u{1b}[0m          6379/tcp\r\n",
        "logs": (1...8).map { "10:24:0\($0) \u{1b}[32mINFO\u{1b}[0m  GET /api/health  200  2ms\r\n" }.joined(),
        "uptime": "10:24:08 up 12 days, 2 users, load average: 0.12, 0.08, 0.05\r\n",
        "uname -a": "Linux atlas 6.8.0-generic aarch64 GNU/Linux\r\n",
        "clear": "\u{1b}[2J\u{1b}[H"
    ]

    static func listing(inSource: Bool, accent: String) -> String {
        if inSource { return "server.ts\r\n" }
        return accent + "src/  config/  logs/  public/\u{1b}[0m\r\nREADME.md  compose.yml  package.json\r\n"
    }
}
#endif
