import Combine
import Foundation

public enum TerminalHistoryAction: CaseIterable {
    case oldest, pageUp, pageDown, latest
}

/// Presentation state only. SwiftTerm owns the viewport, reflow and bounded history.
@MainActor
public final class TerminalHistoryState: ObservableObject {
    public struct Status: Equatable {
        public var canScroll = false
        public var readingHistory = false
        public var hasNewOutput = false
    }

    @Published public private(set) var status = Status()
    private var pending = Status()
    private var updateScheduled = false

    public init() {}

    public func update(canScroll: Bool, position: Double, receivedOutput: Bool = false) {
        let reading = canScroll && position.isFinite && position < 1
        pending = Status(canScroll: canScroll, readingHistory: reading,
                         hasNewOutput: reading && (pending.hasNewOutput || receivedOutput))
        guard !updateScheduled, pending != status else { return }
        updateScheduled = true
        // Native scrolling/resizing can occur inside a SwiftUI representable update.
        // Coalesce output bursts and publish outside that update, without retaining terminal views.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            if self.status != self.pending { self.status = self.pending }
        }
    }
}
