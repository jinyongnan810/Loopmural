import AppKit

/// Opens a native context menu for menu bar right-clicks and Control-clicks.
@MainActor
final class MenuBarExtraRightClickMonitor: NSObject {
    /// The shared instance used throughout the app.
    static let shared = MenuBarExtraRightClickMonitor()

    /// Opens settings from the menu bar context menu.
    var onOpenSettings: (() -> Void)?
    /// The token for the local mouse event monitor.
    private var eventMonitor: Any?

    /// Creates the shared menu bar event monitor.
    override private init() {
        super.init()
    }

    /// Intercepts right-clicks and Control-clicks on the menu bar button.
    func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            let isRightClick = event.type == .rightMouseDown
            let isControlClick = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
            guard isRightClick || isControlClick,
                  let contentView = event.window?.contentView,
                  let button = findStatusBarButton(in: contentView)
            else {
                return event
            }
            showContextMenu(for: button, event: event)
            return nil
        }
    }

    /// Removes the event monitor and clears the settings action.
    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        onOpenSettings = nil
    }

    /// Finds the status bar button within a view hierarchy.
    private func findStatusBarButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton {
            return button
        }
        for subview in view.subviews {
            if let button = findStatusBarButton(in: subview) {
                return button
            }
        }
        return nil
    }

    /// Shows the settings and quit actions beside the menu bar button.
    private func showContextMenu(for button: NSStatusBarButton, event: NSEvent) {
        let menu = NSMenu()
        let settings = NSMenuItem(
            title: String(localized: "Settings"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: "Quit Loopmural"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        button.isHighlighted = true
        defer { button.isHighlighted = false }
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    /// Runs the registered settings action.
    @objc private func openSettings() {
        onOpenSettings?()
    }

    /// Terminates the application.
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
