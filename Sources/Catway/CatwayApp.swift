import AppKit
import Darwin
import SwiftUI

enum RuntimePaths {
    static let temporaryDirectory: URL = {
        if let override = ProcessInfo.processInfo.environment["CATWAY_TMPDIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
    }()
    static let visibilityMarker = temporaryDirectory.appendingPathComponent("catway-visible")
    static let pidFile = temporaryDirectory.appendingPathComponent("catway.pid")
}

final class CatwayOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class CatwayDelegate: NSObject, NSApplicationDelegate {
    private let client: YabaiClient
    private let store: WorkspaceStore
    private let startsVisible: Bool
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var toggleSignal: DispatchSourceSignal?
    private var dismissSignal: DispatchSourceSignal?

    init(client: YabaiClient, spaces: [WorkspaceModel], startsVisible: Bool) {
        self.client = client
        store = WorkspaceStore(spaces: spaces)
        self.startsVisible = startsVisible
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Keep Catway ready for instant workspace switching")
        NSApp.setActivationPolicy(.accessory)
        writePidFile()
        installSignalHandlers()
        installKeyMonitor()

        if startsVisible {
            show()
        } else {
            refreshSpaces()
        }
    }

    private func installSignalHandlers() {
        signal(SIGUSR1, SIG_IGN)
        let toggle = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        toggle.setEventHandler { [weak self] in self?.toggle() }
        toggle.resume()
        toggleSignal = toggle

        signal(SIGUSR2, SIG_IGN)
        let dismiss = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        dismiss.setEventHandler { [weak self] in self?.dismiss() }
        dismiss.resume()
        dismissSignal = dismiss
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true else { return event }
            if event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            if let key = event.charactersIgnoringModifiers?.uppercased(), key.count == 1,
               let workspace = self.store.spaces.first(where: { $0.displayLabel.uppercased() == key }) {
                self.select(workspace)
                return nil
            }
            return event
        }
    }

    private func toggle() {
        window?.isVisible == true ? dismiss() : show()
    }

    private func show() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen = targetScreen else { return }

        let localOrigin = CGPoint(
            x: mouseLocation.x - screen.frame.minX,
            y: screen.frame.maxY - mouseLocation.y
        )
        store.gestureOrigin = localOrigin
        store.visualCenter = localOrigin

        let overview = WorkspaceWheelView(
            store: store,
            select: { [weak self] workspace in self?.select(workspace) },
            dismiss: { [weak self] in self?.dismiss() }
        )

        let overlayWindow: NSWindow
        if let existing = window {
            overlayWindow = existing
            overlayWindow.setFrame(screen.frame, display: false)
            overlayWindow.contentView = makeContentView(for: overview, size: screen.frame.size)
        } else {
            overlayWindow = CatwayOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            overlayWindow.backgroundColor = .clear
            overlayWindow.isOpaque = false
            overlayWindow.hasShadow = false
            overlayWindow.level = .screenSaver
            overlayWindow.animationBehavior = .none
            overlayWindow.contentView = makeContentView(for: overview, size: screen.frame.size)
            window = overlayWindow
        }

        // A reusable all-Spaces window can retain a stale Space association and
        // make AppKit animate away from the user's current workspace on activation.
        overlayWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        overlayWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        FileManager.default.createFile(atPath: RuntimePaths.visibilityMarker.path, contents: Data())
        refreshSpaces()
    }

    private func makeContentView(for overview: WorkspaceWheelView, size: CGSize) -> NSView {
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        let blurView = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        blurView.material = .underWindowBackground
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.alphaValue = 0.42
        blurView.autoresizingMask = [.width, .height]
        container.addSubview(blurView)

        let hostingView = NSHostingView(rootView: overview)
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        return container
    }

    private func dismiss() {
        window?.orderOut(nil)
        try? FileManager.default.removeItem(at: RuntimePaths.visibilityMarker)
    }

    private func select(_ workspace: WorkspaceModel) {
        dismiss()
        let client = client
        DispatchQueue.global(qos: .userInitiated).async {
            try? client.focus(index: workspace.index)
        }
    }

    private func refreshSpaces() {
        let client = client
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let occupiedOnly = CatwayConfiguration.load().hideEmptyWorkspaces
            guard let spaces = try? client.loadWorkspaces(occupiedOnly: occupiedOnly) else { return }
            DispatchQueue.main.async {
                self?.store.spaces = spaces
            }
        }
    }

    private func writePidFile() {
        let data = Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8)
        try? data.write(to: RuntimePaths.pidFile, options: .atomic)
    }

    private func removePidFileIfOwned() {
        guard let data = try? Data(contentsOf: RuntimePaths.pidFile),
              let contents = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              contents == String(ProcessInfo.processInfo.processIdentifier)
        else { return }
        try? FileManager.default.removeItem(at: RuntimePaths.pidFile)
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: RuntimePaths.visibilityMarker)
        removePidFileIfOwned()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        toggleSignal?.cancel()
        dismissSignal?.cancel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct CatwayMain {
    static func main() {
        do {
            let arguments = CommandLine.arguments
            if !arguments.contains("--daemon")
                && !arguments.contains("--wheel")
                && !arguments.contains("--dump-model") {
                let app = NSApplication.shared
                let delegate = SettingsAppDelegate()
                app.delegate = delegate
                app.run()
                _ = delegate
                return
            }

            let client = try YabaiClient()
            let spaces = try client.loadWorkspaces(
                occupiedOnly: CatwayConfiguration.load().hideEmptyWorkspaces
            )
            if arguments.contains("--dump-model") {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(spaces)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
                return
            }

            let app = NSApplication.shared
            let delegate = CatwayDelegate(
                client: client,
                spaces: spaces,
                startsVisible: arguments.contains("--wheel")
            )
            app.delegate = delegate
            app.run()
            _ = delegate
        } catch {
            FileHandle.standardError.write(Data("Catway failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
