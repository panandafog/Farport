import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Separate payload types prevent a host drag from being interpreted as a tab move, or arbitrary text as either.
struct HostDragItem: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.panandafog.harbor.host-order"))
    }
}

struct TerminalTabDragItem: Codable, Transferable {
    let hostID: UUID
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.panandafog.harbor.tab-order"))
    }
}

extension View {
    func reorderableHost(_ id: UUID, move: @escaping (UUID, UUID) -> Void) -> some View {
        hostDragSource(id)
            .dropDestination(for: HostDragItem.self) { items, _ in
                guard items.count == 1, let item = items.first, item.id != id else { return false }
                move(item.id, id)
                return true
            }
    }

    @ViewBuilder
    private func hostDragSource(_ id: UUID) -> some View {
        #if os(macOS)
        draggable(HostDragItem(id: id)) {
            // List owns the sidebar background, so the drag preview needs its own opaque surface.
            self
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
        #else
        draggable(HostDragItem(id: id))
        #endif
    }

    func reorderableTerminal(_ id: UUID, hostID: UUID, move: @escaping (UUID, UUID) -> Void) -> some View {
        draggable(TerminalTabDragItem(hostID: hostID, id: id))
            .dropDestination(for: TerminalTabDragItem.self) { items, _ in
                guard items.count == 1, let item = items.first, item.hostID == hostID, item.id != id else {
                    return false
                }
                move(item.id, id)
                return true
            }
    }
}
