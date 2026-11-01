import FarportLocalization
import FarportSessions
import SwiftUI

struct TerminalAppearanceSettings: View {
    @AppStorage("terminal.colorScheme") private var scheme = TerminalColorScheme.standard.rawValue
    @AppStorage("terminal.followsSystemAppearance") private var followsSystem = true
    @AppStorage("terminal.darkAppearance") private var dark = true
    @AppStorage("terminal.useAppAccent") private var useAppAccent = true

    var body: some View {
        Form {
            Toggle(L10n.text("Follow System Appearance"), isOn: $followsSystem)
            if !followsSystem {
                Picker(L10n.text("Appearance"), selection: $dark) {
                    Text(L10n.text("Light")).tag(false)
                    Text(L10n.text("Dark")).tag(true)
                }.pickerStyle(.segmented)
            }
            Picker(L10n.text("Color Scheme"), selection: $scheme) {
                Text(L10n.text("Default — System Accent")).tag(TerminalColorScheme.standard.rawValue)
                Text(L10n.text("Ocean")).tag(TerminalColorScheme.ocean.rawValue)
                Text(L10n.text("Paper")).tag(TerminalColorScheme.paper.rawValue)
            }
            Text(L10n.text("Applies to all terminals on this device.")).font(.footnote).foregroundStyle(.secondary)
            Toggle(L10n.text("Use App Accent"), isOn: $useAppAccent)
            Text(L10n.text("SSH prompts, tmux panels, cursor and selection."))
                .font(.footnote).foregroundStyle(.secondary)
            Text(L10n.text(
                "Prompt changes apply to new Bash/Zsh shells. Reconnect SSH or open a new tmux tab."
            ))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.text("Terminal Appearance"))
    }
}

struct TerminalAppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TerminalAppearanceSettings()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("Done")) { dismiss() }
                    }
                }
        }.sheetFrame(width: 480, height: 420)
    }
}

/// Observed by each native adapter so retained tabs pick up changes when reattached.
@propertyWrapper
struct TerminalAppearanceStorage: DynamicProperty {
    @AppStorage("terminal.colorScheme") private var scheme = TerminalColorScheme.standard.rawValue
    @AppStorage("terminal.followsSystemAppearance") private var followsSystem = true
    @AppStorage("terminal.darkAppearance") private var dark = true
    @AppStorage("terminal.useAppAccent") private var useAppAccent = true

    /// Native renderers need this before automatic connect/reattach, not only their first SwiftUI update.
    static var current: TerminalAppearance {
        #if DEBUG
        if ScreenshotSupport.requested { return TerminalAppearance() }
        #endif
        let defaults = UserDefaults.standard
        return TerminalAppearance(
            scheme: defaults.string(forKey: "terminal.colorScheme").flatMap(TerminalColorScheme.init) ?? .standard,
            followsSystem: defaults.object(forKey: "terminal.followsSystemAppearance") as? Bool ?? true,
            dark: defaults.object(forKey: "terminal.darkAppearance") as? Bool ?? true,
            useAppAccent: defaults.object(forKey: "terminal.useAppAccent") as? Bool ?? true
        )
    }

    var wrappedValue: TerminalAppearance {
        #if DEBUG
        if ScreenshotSupport.requested { return TerminalAppearance() }
        #endif
        return TerminalAppearance(scheme: TerminalColorScheme(rawValue: scheme) ?? .standard,
                                  followsSystem: followsSystem, dark: dark, useAppAccent: useAppAccent)
    }
}
