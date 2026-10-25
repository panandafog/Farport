#if os(macOS)
import AppKit
#else
import UIKit
#endif
import FarportSessions
import SwiftTerm

extension TerminalView {
    var scrollCellSize: CGSize {
        #if os(macOS)
        let scale = window?.backingScaleFactor ?? 1
        #else
        let scale = window?.contentScaleFactor ?? 1
        #endif
        let pixels = cellSizeInPixels(source: getTerminal()) ?? (width: 1, height: 1)
        return CGSize(width: max(1, CGFloat(pixels.width) / scale), height: max(1, CGFloat(pixels.height) / scale))
    }

    func reportScrollWheel(lines: Int, at point: CGPoint, shift: Bool = false,
                           meta: Bool = false, control: Bool = false) {
        let terminal = getTerminal()
        guard lines != 0, allowMouseReporting, terminal.mouseMode != .off else { return }
        let cell = scrollCellSize
        let column = max(0, min(terminal.cols - 1, Int(point.x / cell.width)))
        let row = max(0, min(terminal.rows - 1, Int(point.y / cell.height)))
        let flags = terminal.encodeButton(button: lines > 0 ? 4 : 5, release: false,
                                          shift: shift, meta: meta, control: control)
        let steps = min(TerminalScrollInput.maximumSteps, lines == Int.min ? Int.max : abs(lines))
        for _ in 0..<steps {
            terminal.sendEvent(buttonFlags: flags, x: column, y: row,
                               pixelX: max(1, Int(point.x) + 1), pixelY: max(1, Int(point.y) + 1))
        }
    }
}
