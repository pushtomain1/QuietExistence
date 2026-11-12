import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let session = Session()
    private lazy var panel = ResponsePanel(session: session)
    private var settingsWindow: NSWindow?
    private var hotKeys: [HotKey] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        ShareProtection.install()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "QuietExistence")

        let menu = NSMenu()
        menu.addItem(item("Summarize Screen  ⌃⌥S", #selector(summarize)))
        menu.addItem(item("Answer Questions on Screen  ⌃⌥A", #selector(answer)))
        menu.addItem(item("Show Panel", #selector(showPanel)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Quit", #selector(NSApplication.terminate(_:)), key: "q"))
        statusItem.menu = menu

        let mods = controlKey | optionKey
        hotKeys = [
            HotKey(keyCode: kVK_ANSI_S, modifiers: mods, id: 1) { [weak self] in self?.summarize() },
            HotKey(keyCode: kVK_ANSI_A, modifiers: mods, id: 2) { [weak self] in self?.answer() },
        ]

        if AgentProvider.current.executablePath() == nil || !CGPreflightScreenCaptureAccess() {
            showSettings()
        }
    }

    /// Opening the app again (Finder / `open`) shows Settings, since the menu bar icon can hide behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    /// Menu bar apps have no main menu by default, which disables ⌘C/⌘V/⌘X/⌘A in text fields.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem(title: "QuietExistence", action: nil, keyEquivalent: ""))
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return item
    }

    @objc private func summarize() { run(.summarize) }
    @objc private func answer() { run(.answer) }

    private func run(_ action: Action) {
        session.captureAndRun(action)
        showPanel()
    }

    @objc private func showPanel() {
        panel.present()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "QuietExistence Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 480, height: 600))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
