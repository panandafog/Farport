import Foundation

struct FinderMutation: Codable, Sendable {
    enum Kind: String, Codable { case create, replace, rename, delete }
    let kind: Kind
    let token: String
    let item: FinderItem
    let destination: String
    let parentIdentifier: String
    let digest: Data?
}
