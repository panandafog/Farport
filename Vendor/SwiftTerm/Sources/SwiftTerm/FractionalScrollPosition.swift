import Foundation

/// Presentation position for the macOS scrollback prototype. Positive deltas go up.
struct FractionalScrollPosition {
    let row: Int
    let fraction: Double

    init(row: Int, fraction: Double, deltaRows: Double, maximumRow: Int) {
        let maximum = Double(max(0, maximumRow))
        let delta = deltaRows.isFinite ? deltaRows : 0
        let remainder = fraction.isFinite ? fraction : 0
        let position = max(0, min(maximum, Double(row) + remainder - delta))
        self.row = Int(position.rounded(.down))
        self.fraction = position - Double(self.row)
    }
}
