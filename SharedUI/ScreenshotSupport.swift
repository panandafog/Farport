#if DEBUG
import FarportCore
import FarportDemo
import FarportLocalization
import FarportSessions
import SwiftUI

/// FramePilot entry points are Debug-only and use the isolated demo library.
enum ScreenshotSupport {
    static var requested: Bool {
        DemoScreenshotScene.isRequested(in: ProcessInfo.processInfo.arguments) &&
            ProcessInfo.processInfo.environment["HARBOR_ISOLATED_TESTS"] != "1"
    }
    static var scene: DemoScreenshotScene? {
        requested ? DemoScreenshotScene.requested(in: ProcessInfo.processInfo.arguments) : nil
    }

    @MainActor
    static func prepare<Terminal>(_ model: HostLibraryModel<Terminal>) {
        guard requested else { model.selectedWorkspace?.terminal?.connect(); return }
        guard let scene, let workspace = model.selectedWorkspace else {
            model.error = L10n.text("Unknown screenshot scene.")
            return
        }
        switch scene {
        case .hosts: model.selection = nil
        case .hostSettings: model.editor = model.hosts.first
        case .files:
            #if os(macOS)
            workspace.mode = .files
            workspace.files.connect()
            #else
            model.error = L10n.text("Unsupported screenshot scene on this platform.")
            #endif
        case .logs:
            workspace.selectedTerminalID = workspace.tabs.dropFirst().first?.id
            workspace.terminal?.connect()
        case .terminal: workspace.terminal?.connect()
        }
    }
}

struct ScreenshotRootModifier<Terminal: TerminalSessionModel>: ViewModifier {
    @ObservedObject var model: HostLibraryModel<Terminal>

    func body(content: Content) -> some View {
        if ScreenshotSupport.requested {
            content.background {
                if let workspace = model.selectedWorkspace {
                    ScreenshotWorkspaceMarker(workspace: workspace)
                } else if ScreenshotSupport.scene == .hosts {
                    Color.clear.frame(width: 1, height: 1).accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.text("Screenshot ready")).accessibilityHidden(false)
                        .accessibilityIdentifier("screen.hosts")
                }
            }
        } else { content }
    }
}

private struct ScreenshotWorkspaceMarker<Terminal: TerminalSessionModel>: View {
    @ObservedObject var workspace: SessionWorkspace<Terminal>

    var body: some View {
        if ScreenshotSupport.scene == .files {
            ScreenshotFilesMarker(files: workspace.files)
        } else if let terminal = workspace.terminal {
            ScreenshotTerminalMarker(terminal: terminal)
        }
    }
}

private struct ScreenshotTerminalMarker: View {
    @ObservedObject var terminal: TerminalSessionModel

    var body: some View {
        if terminal.state == .connected, let scene = ScreenshotSupport.scene,
           scene == .terminal || scene == .logs {
            Color.clear.frame(width: 1, height: 1).accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.text("Screenshot ready")).accessibilityHidden(false)
                .accessibilityIdentifier("screen." + scene.rawValue)
        }
    }
}

private struct ScreenshotFilesMarker: View {
    @ObservedObject var files: FilesModel

    var body: some View {
        if files.connected, !files.busy, !files.entries.isEmpty {
            Color.clear.frame(width: 1, height: 1).accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.text("Screenshot ready")).accessibilityHidden(false)
                .accessibilityIdentifier("screen.files")
        }
    }
}
#endif
