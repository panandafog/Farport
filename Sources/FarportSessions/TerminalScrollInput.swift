import Foundation

public struct TerminalScrollInput {
    public static let historyLimit = 10_000
    public static let maximumSteps = 120
    private var remainder = 0.0

    public init() {}

    public mutating func reset() { remainder = 0 }

    /// Positive deltas move toward older output. Preserve fractional trackpad/touch movement.
    public mutating func lines(for delta: Double) -> Int {
        guard delta.isFinite else { reset(); return 0 }
        if delta * remainder < 0 { remainder = 0 }
        remainder += max(-Double(Self.maximumSteps), min(Double(Self.maximumSteps), delta))
        let lines = Int(remainder.rounded(.towardZero))
        remainder -= Double(lines)
        return lines
    }
}
