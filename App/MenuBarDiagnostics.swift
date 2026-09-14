#if DEBUG
import AppKit
import OSLog

@MainActor
enum MenuBarDiagnostics {
    private static let log = Logger(subsystem: "com.xiaolin.daydo", category: "MenuBar")

    /// Inspect our actual status button, rather than the SwiftUI label's proposed frame.
    static func recordImageGeometry() {
        func buttons(in view: NSView) -> [NSStatusBarButton] {
            (view as? NSStatusBarButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let statusButtons = NSApp.windows.compactMap(\.contentView).flatMap { buttons(in: $0) }
        guard !statusButtons.isEmpty else {
            log.notice("Status button not available for geometry inspection")
            return
        }
        for button in statusButtons {
            guard let image = button.image else { continue }
            let rect = (button.cell as? NSButtonCell)?.imageRect(forBounds: button.bounds) ?? .zero
            let scale = button.window?.backingScaleFactor ?? 1
            log.notice("Image \(image.size.width)x\(image.size.height)pt; draw \(rect.width)x\(rect.height)pt; backing \(scale)x; template \(image.isTemplate)")
        }
    }
}
#endif
