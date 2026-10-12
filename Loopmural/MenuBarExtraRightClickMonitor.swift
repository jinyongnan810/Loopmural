import AppKit

/// Matches C2V's native context menu while leaving ordinary clicks to MenuBarExtra.
@MainActor
final class MenuBarExtraRightClickMonitor: NSObject {
    static let shared = MenuBarExtraRightClickMonitor()

    var onOpenSettings: (() -> Void)?
    private var eventMonitor: Any?

    override private init() {
        super.init()
    }

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

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        onOpenSettings = nil
    }

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

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
