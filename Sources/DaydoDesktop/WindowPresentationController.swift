import AppKit

/// Keeps app presentation separate from the shared task store and background services.
@MainActor
public final class WindowPresentationController: NSObject {
    private let notificationCenter: NotificationCenter
    private let windows: () -> [NSWindow]
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void
    private var isObserving = false

    public init(notificationCenter: NotificationCenter = .default,
                windows: @escaping () -> [NSWindow] = { NSApp.windows },
                setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = {
                    NSApp.setActivationPolicy($0)
                }) {
        self.notificationCenter = notificationCenter
        self.windows = windows
        self.setActivationPolicy = setActivationPolicy
        super.init()
    }

    public func start(background: Bool) {
        guard !isObserving else { return }
        isObserving = true
        notificationCenter.addObserver(self, selector: #selector(windowWillClose(_:)),
                                       name: NSWindow.willCloseNotification, object: nil)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            notificationCenter.addObserver(self, selector: #selector(windowBecameActive(_:)),
                                           name: name, object: nil)
        }
        setActivationPolicy(background ? .accessory : .regular)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, isUserWindow(closingWindow) else { return }
        // willClose is sent while the closing window may still be visible.
        let hasOpenWindow = windows().contains {
            $0 !== closingWindow && isUserWindow($0) && ($0.isVisible || $0.isMiniaturized)
        }
        if !hasOpenWindow { setActivationPolicy(.accessory) }
    }

    @objc private func windowBecameActive(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, isUserWindow(window) else { return }
        setActivationPolicy(.regular)
    }

    private func isUserWindow(_ window: NSWindow) -> Bool {
        // MenuBarExtra and other transient system windows must not keep the Dock icon alive.
        window.styleMask.contains(.titled) && window.level == .normal
    }

    deinit {
        notificationCenter.removeObserver(self)
    }
}
