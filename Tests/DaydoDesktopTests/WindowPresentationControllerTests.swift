import AppKit
import XCTest
@testable import DaydoDesktop

@MainActor
final class WindowPresentationControllerTests: XCTestCase {
    func testClosingLastWindowRemovesDockEntryEvenBeforeAppKitMarksItHidden() async {
        let app = Harness()
        let main = app.addWindow()
        app.controller.start(background: false)

        app.center.post(name: NSWindow.willCloseNotification, object: main)

        XCTAssertTrue(main.isVisible, "willClose arrives before AppKit changes visibility")
        XCTAssertEqual(app.policies.last, .accessory)
    }

    func testReopeningTheSameWindowRestoresDockEntry() async {
        let app = Harness()
        let main = app.addWindow()
        app.controller.start(background: false)
        app.center.post(name: NSWindow.willCloseNotification, object: main)
        app.center.post(name: NSWindow.didBecomeKeyNotification, object: main)
        app.center.post(name: NSWindow.willCloseNotification, object: main)
        app.center.post(name: NSWindow.didBecomeMainNotification, object: main)

        XCTAssertEqual(app.policies, [.regular, .accessory, .regular, .accessory, .regular])
    }

    func testSettingsStayInDockUntilTheLastUserWindowCloses() async {
        let app = Harness()
        let main = app.addWindow()
        let settings = app.addWindow()
        app.controller.start(background: false)
        app.center.post(name: NSWindow.willCloseNotification, object: main)
        main.reportedVisible = false

        XCTAssertEqual(app.policies.last, .regular)
        app.center.post(name: NSWindow.willCloseNotification, object: settings)
        XCTAssertEqual(app.policies.last, .accessory)
    }

    func testMinimizedMainWindowKeepsDockAccessWhenSettingsClose() async {
        let app = Harness()
        let main = app.addWindow()
        let settings = app.addWindow()
        app.controller.start(background: false)
        main.reportedVisible = false
        main.reportedMiniaturized = true
        app.center.post(name: NSWindow.didMiniaturizeNotification, object: main)
        app.center.post(name: NSWindow.willCloseNotification, object: settings)

        XCTAssertEqual(app.policies.last, .regular)
    }

    func testMenuBarWindowsDoNotKeepDockEntryOrBringItBack() async {
        let app = Harness()
        let main = app.addWindow()
        let menu = app.addWindow(styleMask: .borderless)
        app.controller.start(background: false)
        app.center.post(name: NSWindow.willCloseNotification, object: main)
        main.reportedVisible = false
        app.center.post(name: NSWindow.didBecomeKeyNotification, object: menu)
        app.center.post(name: NSWindow.willCloseNotification, object: menu)

        XCTAssertEqual(app.policies, [.regular, .accessory])
    }

    func testBackgroundLaunchStaysOutOfDockUntilAUserWindowOpens() async {
        let app = Harness()
        app.controller.start(background: true)
        XCTAssertEqual(app.policies, [.accessory])

        let main = app.addWindow()
        app.center.post(name: NSWindow.didBecomeMainNotification, object: main)
        XCTAssertEqual(app.policies, [.accessory, .regular])
    }

    func testHiddenRetainedWindowsDoNotKeepDockEntry() async {
        let app = Harness()
        let retained = app.addWindow()
        retained.reportedVisible = false
        let main = app.addWindow()
        app.controller.start(background: false)
        app.center.post(name: NSWindow.willCloseNotification, object: main)

        XCTAssertEqual(app.policies.last, .accessory)
    }
}

@MainActor
private final class Harness {
    let center = NotificationCenter()
    var windows: [TestWindow] = []
    var policies: [NSApplication.ActivationPolicy] = []
    lazy var controller = WindowPresentationController(
        notificationCenter: center,
        windows: { [unowned self] in windows },
        setActivationPolicy: { [unowned self] in policies.append($0) }
    )

    func addWindow(styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]) -> TestWindow {
        _ = NSApplication.shared
        let window = TestWindow(contentRect: .zero, styleMask: styleMask, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        windows.append(window)
        return window
    }
}

@MainActor
private final class TestWindow: NSWindow {
    var reportedVisible = true
    var reportedMiniaturized = false
    override var isVisible: Bool { reportedVisible }
    override var isMiniaturized: Bool { reportedMiniaturized }
}
