import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = IslandController()
    private let listener = Listener()
    private var panel: IslandPanel?
    private var statusItem: NSStatusItem?
    private var currentSubscription: AnyCancellable?
    private var islandStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.rotateIfBig()
        Log.write("---- Island for Mac starting. macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // Only one island at a time.
        if let id = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                Log.write("Another Island is already running; quitting this copy.")
                NSApp.terminate(nil)
                return
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Island") {
            statusItem?.button?.image = image
        } else {
            statusItem?.button?.title = "Island"
        }

        // Locked until the owner's signed activation code has been entered on this Mac.
        if Activation.isActivated {
            Log.write("Activation: valid code found.")
            startIsland()
        } else {
            Log.write("Activation: locked. Device ID \(Activation.deviceID). Nothing is shown until a code is pasted.")
        }
        rebuildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        listener.stop()
        Log.write("Island for Mac quitting.")
    }

    // MARK: starting the island (only once activated)

    private func startIsland() {
        guard !islandStarted else { return }
        islandStarted = true

        controller.sendToConnection = { [weak self] text, connection in self?.listener.send(text, to: connection) }
        listener.onLine = { [weak self] line, connection in self?.controller.submit(line, from: connection) }
        listener.start()

        // While nothing is showing the island ignores the mouse, so it never gets in the way.
        currentSubscription = controller.$current.sink { [weak self] message in
            self?.panel?.ignoresMouseEvents = (message == nil)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        screensChanged()
    }

    @objc private func screensChanged() {
        guard let screen = ScreenInfo.builtInScreen() else {
            Log.write("No built-in screen found (lid closed?): island hidden.")
            panel?.orderOut(nil)
            return
        }
        let geo = ScreenInfo.geometry(for: screen)
        controller.geo = geo

        let width = controller.windowWidth
        let height = controller.windowHeight
        let frame = NSRect(x: geo.screenFrame.midX - width / 2,
                           y: geo.screenFrame.maxY - height,
                           width: width, height: height)

        if panel == nil {
            let newPanel = IslandPanel(frame: frame)
            let host = FirstClickHostingView(rootView: IslandView(controller: controller))
            host.frame = NSRect(origin: .zero, size: frame.size)
            newPanel.contentView = host
            panel = newPanel
        }
        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
        Log.write("Island placed on built-in screen: notch=\(geo.hasNotch) rest=\(Int(geo.restWidth))x\(Int(geo.restHeight)) window=\(frame)")
    }

    // MARK: menu-bar item (always there: activate, test, read the log, quit)

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?, key: String = "") {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        if action == nil { item.isEnabled = false }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        if islandStarted {
            add(menu, "Show a test message", #selector(testAlert))
            add(menu, "Show a test with buttons", #selector(testButtons))
            add(menu, "Show a progress test", #selector(testProgress))
            add(menu, "Show an urgent test", #selector(testUrgent))
            menu.addItem(.separator())
        } else {
            add(menu, "Island is locked", nil)
            add(menu, "Paste activation code from clipboard", #selector(pasteCode))
            menu.addItem(.separator())
        }
        add(menu, "Copy my Device ID (\(Activation.deviceID))", #selector(copyDeviceID))
        add(menu, "Open the log file", #selector(openLog))
        add(menu, "Show the log in Finder", #selector(showLog))
        menu.addItem(.separator())
        add(menu, "Quit Island", #selector(quit), key: "q")
        statusItem?.menu = menu
    }

    private func say(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    @objc private func pasteCode() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        switch Activation.check(text) {
        case .valid:
            Activation.save(text)
            Log.write("Activation: code accepted.")
            startIsland()
            rebuildMenu()
            say("Island is activated", "Thank you. Use the capsule icon in the menu bar and choose \"Show a test message\" to try it.")
        case .invalid(let reason):
            Log.write("Activation: code refused (\(reason))")
            say("That code did not work", reason + "\n\nCopy the whole code from the owner's message first, then choose this menu item again.")
        }
    }

    @objc private func copyDeviceID() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Activation.deviceID, forType: .string)
    }

    @objc private func testAlert() {
        controller.submit("{\"version\":1,\"id\":\"mac-test-alert\",\"source\":\"test\",\"kind\":\"alert\",\"title\":\"Island is working\",\"body\":\"A test message on your Mac\",\"category\":\"#4F8CFF\",\"duration\":6}", from: nil)
    }

    @objc private func testButtons() {
        controller.submit("{\"version\":1,\"id\":\"mac-test-buttons\",\"source\":\"test\",\"kind\":\"alert\",\"title\":\"Stand-up in 5 minutes\",\"body\":\"Room 2, with the design team\",\"category\":\"#4F8CFF\",\"duration\":12,\"actions\":[{\"id\":\"snooze\",\"label\":\"Snooze\"},{\"id\":\"open\",\"label\":\"Open\"}]}", from: nil)
    }

    @objc private func testProgress() {
        controller.submit("{\"version\":1,\"id\":\"mac-test-progress\",\"source\":\"test\",\"kind\":\"progress\",\"title\":\"Downloading update\",\"body\":\"65 percent\",\"progress\":0.65,\"category\":\"#34C759\",\"duration\":8}", from: nil)
    }

    @objc private func testUrgent() {
        controller.submit("{\"version\":1,\"id\":\"mac-test-urgent\",\"source\":\"test\",\"kind\":\"alert\",\"title\":\"Battery is very low\",\"body\":\"Plug in soon\",\"category\":\"#FF453A\",\"priority\":\"high\",\"duration\":6}", from: nil)
    }

    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }

    @objc private func showLog() { NSWorkspace.shared.activateFileViewerSelecting([Log.url]) }

    @objc private func quit() { NSApp.terminate(nil) }
}
