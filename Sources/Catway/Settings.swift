import AppKit
import Foundation
import SwiftUI

struct CatwaySettings: Codable, Equatable, Sendable {
    var fourFingerGestures = true
    var horizontalWorkspaceSwipe = false
    var doubleBacktick = true
    var bareWorkspaceKeys = true
    var keyboardShortcuts = true
    var sketchyBarIntegration = true
    var hideEmptyWorkspaces = true
    var disableNativeMissionControl = true

    static let defaults = CatwaySettings()
}

enum CatwayConfiguration {
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["CATWAY_CONFIG_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("catway", isDirectory: true)
    }

    static var settingsFile: URL {
        directory.appendingPathComponent("settings.json")
    }

    static func load() -> CatwaySettings {
        guard let data = try? Data(contentsOf: settingsFile),
              let settings = try? JSONDecoder().decode(CatwaySettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    static func save(_ settings: CatwaySettings) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        try data.write(to: settingsFile, options: .atomic)
    }
}

struct CommandOutput: Sendable {
    let status: Int32
    let output: String
}

enum CatwayCompanion {
    static func executable() -> String? {
        let fileManager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["CATWAY_CLI"],
            Bundle.main.resourceURL?.appendingPathComponent("scripts/catway").path,
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/catway").path,
            "/opt/homebrew/bin/catway",
            "/usr/local/bin/catway",
        ].compactMap { $0 }
        return candidates.first(where: fileManager.isExecutableFile(atPath:))
    }

    static func run(_ arguments: [String]) -> CommandOutput {
        guard let executable = executable() else {
            return CommandOutput(status: 127, output: "Catway command not found. Re-run the installer.")
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CommandOutput(status: process.terminationStatus, output: output)
        } catch {
            return CommandOutput(status: 1, output: error.localizedDescription)
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings = CatwayConfiguration.load()
    @Published var statusMessage = "Ready"
    @Published var isApplying = false

    func apply() {
        isApplying = true
        statusMessage = "Applying…"
        let snapshot = settings
        Task.detached {
            do {
                try CatwayConfiguration.save(snapshot)
                let result = CatwayCompanion.run(["sync-settings"])
                await MainActor.run {
                    self.isApplying = false
                    self.statusMessage = result.status == 0 ? "Settings applied" : result.output
                }
            } catch {
                await MainActor.run {
                    self.isApplying = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func runDoctor() {
        isApplying = true
        statusMessage = "Checking Catway…"
        Task.detached {
            let result = CatwayCompanion.run(["doctor", "--summary"])
            await MainActor.run {
                self.isApplying = false
                self.statusMessage = result.output.isEmpty ? "Doctor finished" : result.output
            }
        }
    }

    func revealConfiguration() {
        try? FileManager.default.createDirectory(at: CatwayConfiguration.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([CatwayConfiguration.settingsFile])
    }
}

struct SettingsToggle: View {
    let title: String
    let detail: String
    @Binding var value: Bool

    var body: some View {
        Toggle(isOn: $value) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}

struct CatwaySettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Catway")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Workspace control for lazy cats who still want to move fast.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    GroupBox("Mission wheel") {
                        VStack(spacing: 14) {
                            SettingsToggle(
                                title: "Four-finger wheel",
                                detail: "Swipe up to open Catway and down to close it.",
                                value: $model.settings.fourFingerGestures
                            )
                            SettingsToggle(
                                title: "Active-only horizontal swipe",
                                detail: "Replaces macOS's animated swipe with instant cycling through active workspaces.",
                                value: $model.settings.horizontalWorkspaceSwipe
                            )
                            SettingsToggle(
                                title: "Disable native Mission Control gesture",
                                detail: "Prevents macOS from opening behind Catway. Reversible on uninstall.",
                                value: $model.settings.disableNativeMissionControl
                            )
                            SettingsToggle(
                                title: "Double backtick",
                                detail: "Double ` opens the wheel; a third press closes it.",
                                value: $model.settings.doubleBacktick
                            )
                            SettingsToggle(
                                title: "Bare workspace keys in the wheel",
                                detail: "Press a workspace label such as Z or V without Option while open.",
                                value: $model.settings.bareWorkspaceKeys
                            )
                        }
                        .padding(8)
                    }

                    GroupBox("Keyboard and workspaces") {
                        VStack(spacing: 14) {
                            SettingsToggle(
                                title: "Catway keyboard shortcuts",
                                detail: "Loads a separate skhd file; your existing skhdrc stays yours.",
                                value: $model.settings.keyboardShortcuts
                            )
                            SettingsToggle(
                                title: "Show only active workspaces",
                                detail: "Empty workspaces disappear and return when a window is moved to them.",
                                value: $model.settings.hideEmptyWorkspaces
                            )
                        }
                        .padding(8)
                    }

                    GroupBox("SketchyBar") {
                        SettingsToggle(
                            title: "Workspace indicators",
                            detail: "Installs an optional Catway plugin without replacing your bar, colors, or layout.",
                            value: $model.settings.sketchyBarIntegration
                        )
                        .padding(8)
                    }
                }
                .padding(22)
            }

            Divider()

            HStack {
                Text(model.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Show config", action: model.revealConfiguration)
                Button("Run doctor", action: model.runDoctor)
                Button("Apply") { model.apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isApplying)
            }
            .padding(16)
        }
        .frame(width: 620, height: 700)
    }
}

@MainActor
final class SettingsAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private let model = SettingsViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let view = CatwaySettingsView(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Catway Settings"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}
