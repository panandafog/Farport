import FarportLocalization
import FarportSessions
import SwiftUI

struct TerminalPastePresentation: ViewModifier {
    @ObservedObject var review: TerminalPasteReview
    let send: (String) -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $review.request) { request in
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("Paste Multiple Lines?")).font(.headline)
                Text(L10n.text("Pasted line breaks may execute commands. Review the text before sending it."))
                ScrollView {
                    Text(request.text).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button(L10n.text("Cancel"), role: .cancel) { review.cancel() }
                    Button(L10n.text("Paste")) {
                        if let text = review.confirm(request.id) { send(text) }
                    }
                }
            }
            .padding().frame(minWidth: 280, minHeight: 250)
            #if os(macOS)
            .frame(width: 560, height: 400)
            #endif
        }
    }
}
