#if DEBUG
import FarportCore
import Foundation

actor DemoFileSession: RemoteFileSession {
    private let home = "/home/alex/app"
    private var directories: Set<String> = ["/", "/home", "/home/alex", "/home/alex/app",
        "/home/alex/app/src", "/home/alex/app/config", "/home/alex/app/logs", "/home/alex/app/public"]
    private var files: [String: Data] = [
        "/home/alex/app/README.md": Data("# Atlas API\n\nA small service for a connected world.\n".utf8),
        "/home/alex/app/compose.yml": Data("services:\n  api:\n    image: atlas-api:latest\n".utf8),
        "/home/alex/app/package.json": Data("{\"name\":\"atlas-api\",\"version\":\"1.4.0\"}\n".utf8),
        "/home/alex/app/src/server.ts": Data("console.log('Atlas API ready');\n".utf8),
        "/home/alex/app/config/app.yml": Data("port: 8080\nlogLevel: info\n".utf8),
        "/home/alex/app/logs/access.log": Data("10:24:08 INFO GET /api/health 200 2ms\n".utf8)
    ]

    func canonicalPath(_ path: String) throws -> String {
        let normalized = normalize(path)
        guard directories.contains(normalized) || files[normalized] != nil else { throw failure("path not found") }
        return normalized
    }

    func list(_ path: String) throws -> [RemoteEntry] {
        let path = normalize(path)
        guard directories.contains(path) else { throw failure("directory not found") }
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let folders = directories.filter { $0 != path && RemotePath.parent(of: $0) == path }.map {
            RemoteEntry(path: $0, name: name($0), kind: .directory, size: nil, modified: date)
        }
        let entries = files.filter { RemotePath.parent(of: $0.key) == path }.map {
            RemoteEntry(path: $0.key, name: name($0.key), kind: .file, size: UInt64($0.value.count), modified: date)
        }
        return (folders + entries).sorted { $0.name < $1.name }
    }

    func createDirectory(_ path: String) throws {
        let path = normalize(path)
        try ensureVacant(path)
        directories.insert(path)
    }

    func rename(_ path: String, to destination: String) throws {
        let source = try canonicalPath(path), target = normalize(destination)
        guard source != "/", source != target else { throw failure("cannot rename this path") }
        try ensureVacant(target)
        guard !target.hasPrefix(source + "/") else { throw failure("invalid destination") }
        if let data = files.removeValue(forKey: source) { files[target] = data; return }
        let descendants = directories.filter { $0 == source || $0.hasPrefix(source + "/") }
        for path in descendants { directories.remove(path); directories.insert(target + path.dropFirst(source.count)) }
        for (path, data) in files.filter({ $0.key.hasPrefix(source + "/") }) {
            files.removeValue(forKey: path)
            files[target + path.dropFirst(source.count)] = data
        }
    }

    func remove(_ entry: RemoteEntry) throws {
        let path = try canonicalPath(entry.path)
        if directories.contains(path) {
            guard path != "/", try list(path).isEmpty else { throw failure("directory is not empty") }
            directories.remove(path)
        } else { files.removeValue(forKey: path) }
    }

    func download(_ path: String, to destination: URL, progress: @escaping TransferProgress) async throws {
        try Task.checkCancellation()
        guard let data = files[normalize(path)] else { throw failure("file not found") }
        try data.write(to: destination, options: .atomic)
        await progress(UInt64(data.count), UInt64(data.count))
    }

    func upload(_ source: URL, to path: String, progress: @escaping TransferProgress) async throws {
        try Task.checkCancellation()
        let path = normalize(path)
        guard directories.contains(RemotePath.parent(of: path)), !directories.contains(path) else {
            throw failure("invalid destination")
        }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1_048_576 else { throw failure("sample uploads are limited to 1 MB") }
        let data = try Data(contentsOf: source)
        files[path] = data
        await progress(UInt64(data.count), UInt64(data.count))
    }

    func close() async {}

    private func ensureVacant(_ path: String) throws {
        guard directories.contains(RemotePath.parent(of: path)),
              !directories.contains(path), files[path] == nil else { throw failure("path exists or parent is missing") }
    }
    private func name(_ path: String) -> String { String(path.split(separator: "/").last ?? "") }
    private func failure(_ message: String) -> Error { HarborError.message("sample server: " + message) }
    private func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        let absolute = path.hasPrefix("/") ? path : home + "/" + path
        for part in absolute.split(separator: "/") {
            if part == ".." { if !parts.isEmpty { parts.removeLast() } } else if part != "." { parts.append(part) }
        }
        return "/" + parts.joined(separator: "/")
    }
}
#endif
