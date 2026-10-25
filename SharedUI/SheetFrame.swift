import SwiftUI

extension View {
    @ViewBuilder
    func sheetFrame(width: CGFloat, height: CGFloat? = nil) -> some View {
        #if os(macOS)
        self.frame(width: width, height: height ?? 480)
        #else
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
            .presentationDragIndicator(.visible)
        #endif
    }
}
