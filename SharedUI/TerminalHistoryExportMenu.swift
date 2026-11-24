import FarportCore
import FarportLocalization
import FarportSessions
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct TerminalHistoryExportMenu: View {
    @ObservedObject var model: TerminalSessionModel
    @ObservedObject var exporter: TerminalHistoryExporter

    var body: some View {
        Menu {
            if exporter.busy {
                Button(L10n.text("Cancel History Export"), role: .cancel, action: exporter.cancel)
            } else {
                actions(for: .local)
                if model.usesTmux {
                    Divider()
                    actions(for: .tmux)
                        .disabled(!model.canReadTmuxHistory)
                }
            }
        } label: {
            Label(L10n.text(exporter.busy ? "Reading History…" : "Export History"),
                  systemImage: exporter.busy ? "hourglass" : "square.and.arrow.up")
        }
    }

    private func actions(for source: TerminalHistorySource) -> some View {
        Menu(source.label) {
            Button(L10n.text("Copy History"), systemImage: "doc.on.doc") {
                exporter.capture(model, source: source, save: false)
            }
            Button(L10n.text("Save History…"), systemImage: "doc.badge.arrow.up") {
                exporter.capture(model, source: source, save: true)
            }
        }
    }
}

/// Attach to the stable terminal/workspace, not transient Menu contents (especially on iOS).
struct TerminalHistoryExportPresentation: ViewModifier {
    @ObservedObject var exporter: TerminalHistoryExporter
    let terminalID: UUID?

    func body(content: Content) -> some View {
        content
            .fileExporter(isPresented: $exporter.exporting, document: exporter.document, contentType: .plainText,
                          defaultFilename: exporter.filename) { result in
                exporter.document = nil
                if case .failure(let failure) = result,
                   (failure as? CocoaError)?.code != .userCancelled { exporter.error = failure.localizedDescription }
            }
            .alert(L10n.text("Could Not Export History"), isPresented: Binding(
                get: { exporter.error != nil }, set: { if !$0 { exporter.error = nil } }
            )) {
                Button(L10n.text("OK"), role: .cancel) { exporter.error = nil }
            } message: { Text(exporter.error ?? "") }
            .onChange(of: terminalID) { _, _ in exporter.cancel() }
            .onDisappear(perform: exporter.cancel)
    }
}

@MainActor
final class TerminalHistoryExporter: ObservableObject {
    @Published private(set) var busy = false
    @Published var document: TerminalHistoryDocument?
    @Published var exporting = false
    @Published var filename = "Farport-history"
    @Published var error: String?
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    func capture(_ model: TerminalSessionModel, source: TerminalHistorySource, save: Bool) {
        cancel()
        let token = requestID
        busy = true
        task = Task { @MainActor in
            do {
                let text = try await model.historySnapshot(from: source)
                try Task.checkCancellation()
                guard token == requestID else { return }
                guard !text.isEmpty else { throw HarborError.message(L10n.text("No terminal history is available.")) }
                if save {
                    filename = "Farport-\(source.rawValue)-history-" +
                        ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                    document = TerminalHistoryDocument(text: text)
                    exporting = true
                } else {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    #else
                    UIPasteboard.general.string = text
                    #endif
                }
            } catch is CancellationError {
                // Closing/switching a tab or cancelling must never copy a late result.
            } catch {
                if token == requestID, !Task.isCancelled { self.error = error.localizedDescription }
            }
            if token == requestID { busy = false; task = nil }
        }
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
        busy = false
    }
}

struct TerminalHistoryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
