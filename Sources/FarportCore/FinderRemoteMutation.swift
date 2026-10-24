import Foundation

extension FinderRemoteReader {
    public func create(_ request: FinderCreateRequest,
                       progress: @escaping TransferProgress) async throws -> FinderItem? {
        try await serialized {
            guard self.writable else { throw FinderWriteError.readOnly }
            return try await self.createUnlocked(request, progress: progress)
        }
    }

    func createUnlocked(_ request: FinderCreateRequest,
                        progress: @escaping TransferProgress) async throws -> FinderItem? {
        let parent = try await itemUnlocked(request.parentIdentifier)
        guard parent.isDirectory else { throw FinderWriteError.unsupportedItem }
        let path = try childPath(request.name, in: parent.relativePath)
        let digest = try request.contents.map(FileDigest.sha256)
        let remote = try await lookup(path)
        if let remote {
            var matchingContent = remote.isDirectory && request.isDirectory
            if !remote.isDirectory, let digest { matchingContent = try await remoteDigest(path) == digest }
            let receipt = catalog.creationReceipts?[request.token]
            if let receipt, remote.isDirectory == request.isDirectory {
                let known = catalog.allItems.first { $0.identifier == receipt && $0.relativePath == path }
                if let known, matchingContent {
                    return known
                }
            }
            if request.mayAlreadyExist, remote.isDirectory == request.isDirectory,
               request.contents == nil || matchingContent {
                return try await record(remote, parent: request.parentIdentifier)
            }
            throw FinderWriteError.collision(try await record(remote, parent: request.parentIdentifier))
        }
        if request.mayAlreadyExist, !request.isDirectory, request.contents == nil { return nil }
        guard request.isDirectory || request.contents != nil else { throw FinderWriteError.unsupportedItem }
        let value = try FinderItem(relativePath: path, isDirectory: request.isDirectory,
                                   identifier: UUID().uuidString, parentIdentifier: request.parentIdentifier)
        let pending = FinderMutation(kind: .create, token: request.token, item: value, destination: path,
                                     parentIdentifier: request.parentIdentifier, digest: digest)
        try prepare(pending)
        let absolute = try FinderPath.remotePath(path, root: rootPath)
        let activity = RemoteFileRequest.Activity()
        try await RemoteFileRequest.perform(activity: activity, factory: factory, action: { session in
            try await self.validateParent(of: path, session: session)
            if request.isDirectory {
                try await session.createDirectory(absolute)
            } else if let contents = request.contents {
                try await session.upload(contents, to: absolute) { completed, total in
                    await activity.recordProgress()
                    await progress(completed, total)
                }
            }
        })
        return try await finish(pending)
    }

    public func modify(_ request: FinderModifyRequest, progress: @escaping TransferProgress
    ) async throws -> FinderWriteResult {
        try await serialized {
            guard self.writable, request.identifier != FinderPath.rootIdentifier else {
                throw FinderWriteError.readOnly
            }
            let current = try await self.itemUnlocked(request.identifier)
            let parentID = request.parentIdentifier ?? current.parentIdentifier
            let parent = try await self.itemUnlocked(parentID)
            guard parent.isDirectory else { throw FinderWriteError.unsupportedItem }
            let destination = try self.childPath(request.name ?? current.name, in: parent.relativePath)
            guard !current.isDirectory || !destination.hasPrefix(current.relativePath + "/") else {
                throw FinderWriteError.unsupportedItem
            }
            if let contents = request.contents {
                guard !current.isDirectory, destination == current.relativePath else {
                    throw FinderWriteError.unsupportedItem
                }
                return try await self.replaceUnlocked(current, request: request, contents: contents, progress: progress)
            }
            guard request.baseVersion == current.contentVersion else { throw FinderWriteError.conflict }
            if destination == current.relativePath { return FinderWriteResult(item: current) }
            if let collision = try await self.lookup(destination) {
                throw FinderWriteError.collision(try await self.record(collision, parent: parentID))
            }
            let pending = FinderMutation(kind: .rename, token: UUID().uuidString, item: current,
                                         destination: destination, parentIdentifier: parentID, digest: current.digest)
            try self.prepare(pending)
            let source = try FinderPath.remotePath(current.relativePath, root: self.rootPath)
            let target = try FinderPath.remotePath(destination, root: self.rootPath)
            try await self.withSession { session in
                try await self.validateParent(of: current.relativePath, session: session)
                try await self.validateParent(of: destination, session: session)
                try await session.rename(source, to: target)
            }
            return FinderWriteResult(item: try await self.finish(pending))
        }
    }

    private func replaceUnlocked(_ current: FinderItem, request: FinderModifyRequest, contents: URL,
                                 progress: @escaping TransferProgress) async throws -> FinderWriteResult {
        let digest = try FileDigest.sha256(contents)
        let remoteHash = try await remoteDigest(current.relativePath)
        if remoteHash == digest {
            let value = try current.identified(current.identifier, parent: current.parentIdentifier, digest: digest)
            var updated = catalog
            updated.upsert(value)
            try save(updated)
            return FinderWriteResult(item: value)
        }
        guard request.baseVersion == current.contentVersion,
              let baseline = current.digest, baseline == remoteHash else {
            return try await keepConflictCopy(current, request: request, digest: digest, progress: progress)
        }
        let pending = FinderMutation(kind: .replace, token: UUID().uuidString, item: current,
                                     destination: current.relativePath, parentIdentifier: current.parentIdentifier,
                                     digest: digest)
        try prepare(pending)
        let path = try FinderPath.remotePath(current.relativePath, root: rootPath)
        let expected = RemoteFileRevision(size: current.size, modified: current.modified, digest: baseline)
        let activity = RemoteFileRequest.Activity()
        do {
            try await RemoteFileRequest.perform(activity: activity, factory: factory, action: { session in
                guard let replacing = session as? any RemoteFileReplacingSession else {
                    throw FinderWriteError.unsupportedReplacement
                }
                try await self.validateParent(of: current.relativePath, session: session)
                guard try await session.canonicalPath(path) == path else { throw FinderReadError.outsideRoot }
                try await replacing.replaceContents(contents, at: path, expected: expected) { completed, total in
                    await activity.recordProgress()
                    await progress(completed, total)
                }
            })
        } catch FinderWriteError.conflict {
            var updated = catalog
            updated.pending = nil
            try save(updated)
            return try await keepConflictCopy(current, request: request, digest: digest, progress: progress)
        }
        return FinderWriteResult(item: try await finish(pending))
    }

    private func keepConflictCopy(_ current: FinderItem, request: FinderModifyRequest, digest: Data,
                                  progress: @escaping TransferProgress) async throws -> FinderWriteResult {
        let suffix = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        let name = current.name as NSString
        let ext = name.pathExtension
        let stem = name.deletingPathExtension
        let conflictName = String(stem.prefix(120)) + " (Harbor conflict " + suffix + ")" +
            (ext.isEmpty ? "" : "." + ext)
        let request = FinderCreateRequest(token: "conflict-" + current.identifier + "-" + suffix,
                                           parentIdentifier: current.parentIdentifier, name: conflictName,
                                           isDirectory: false, contents: request.contents)
        _ = try await createUnlocked(request, progress: progress)
        // Both versions now exist remotely. Fetch the server original back into the edited item.
        return FinderWriteResult(item: try await itemUnlocked(current.identifier), refetchContents: true)
    }

    public func delete(_ identifier: String, baseVersion: Data) async throws {
        try await serialized {
            guard self.writable, identifier != FinderPath.rootIdentifier else { throw FinderWriteError.readOnly }
            guard self.catalog.allItems.contains(where: { $0.identifier == identifier }) else { return }
            let item: FinderItem
            do { item = try await self.itemUnlocked(identifier) } catch FinderReadError.noSuchItem { return }
            guard baseVersion == item.contentVersion else { throw FinderWriteError.conflict }
            if item.isDirectory {
                let children = try await self.listUnlocked(identifier)
                guard children.isEmpty else { throw FinderWriteError.directoryNotEmpty }
            } else if let digest = item.digest {
                guard try await self.remoteDigest(item.relativePath) == digest else { throw FinderWriteError.conflict }
            }
            let pending = FinderMutation(kind: .delete, token: UUID().uuidString, item: item,
                                         destination: item.relativePath, parentIdentifier: item.parentIdentifier,
                                         digest: nil)
            try self.prepare(pending)
            let path = try FinderPath.remotePath(item.relativePath, root: self.rootPath)
            try await self.withSession { session in
                try await self.validateParent(of: item.relativePath, session: session)
                try await session.remove(RemoteEntry(path: path, name: item.name,
                                                     kind: item.isDirectory ? .directory : .file,
                                                     size: item.size, modified: item.modified))
            }
            try self.finishDeletion(pending)
        }
    }
}
