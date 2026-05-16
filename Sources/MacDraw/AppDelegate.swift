import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlayManager = OverlayManager()
    private var controlPanelController: ControlPanelController?
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var globalFlagsMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        installEventMonitors()

        overlayManager.start()

        let controlPanelController = ControlPanelController(overlayManager: overlayManager)
        self.controlPanelController = controlPanelController
        controlPanelController.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
        }
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlayManager.showOverlays()
        controlPanelController?.showWindow(nil)
        controlPanelController?.window?.deminiaturize(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit MacDraw",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

    private func installEventMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.overlayManager.disableDrawing()
            return nil
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateTemporaryDrawingState(with: event.modifierFlags)
            return event
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async {
                self?.updateTemporaryDrawingState(with: event.modifierFlags)
            }
        }
    }

    private func updateTemporaryDrawingState(with flags: NSEvent.ModifierFlags) {
        overlayManager.setTemporaryDrawingEnabled(flags.contains(.control))
    }
}
