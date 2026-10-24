import Foundation

public struct FinderCreateRequest: Sendable {
    public let token: String
    public let parentIdentifier: String
    public let name: String
    public let isDirectory: Bool
    public let contents: URL?
    public let mayAlreadyExist: Bool

    public init(token: String, parentIdentifier: String, name: String, isDirectory: Bool,
                contents: URL?, mayAlreadyExist: Bool = false) {
        self.token = token
        self.parentIdentifier = parentIdentifier
        self.name = name
        self.isDirectory = isDirectory
        self.contents = contents
        self.mayAlreadyExist = mayAlreadyExist
    }
}

public struct FinderModifyRequest: Sendable {
    public let identifier: String
    public let baseVersion: Data
    public let name: String?
    public let parentIdentifier: String?
    public let contents: URL?

    public init(identifier: String, baseVersion: Data, name: String? = nil,
                parentIdentifier: String? = nil, contents: URL? = nil) {
        self.identifier = identifier
        self.baseVersion = baseVersion
        self.name = name
        self.parentIdentifier = parentIdentifier
        self.contents = contents
    }
}

public struct FinderWriteResult: Sendable {
    public let item: FinderItem
    public let refetchContents: Bool

    public init(item: FinderItem, refetchContents: Bool = false) {
        self.item = item
        self.refetchContents = refetchContents
    }
}
