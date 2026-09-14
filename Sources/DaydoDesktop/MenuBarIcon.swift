import AppKit

@MainActor
public enum MenuBarIcon {
    /// A 16pt ink diameter is 32px on a 2x display, matching adjacent menu bar icons.
    /// MenuBarExtra extracts its label's NSImage and does not honor SwiftUI frame modifiers.
    public static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { bounds in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: bounds).fill()

            let check = NSBezierPath()
            check.move(to: NSPoint(x: bounds.width * 0.27, y: bounds.height * 0.49))
            check.line(to: NSPoint(x: bounds.width * 0.43, y: bounds.height * 0.31))
            check.line(to: NSPoint(x: bounds.width * 0.73, y: bounds.height * 0.71))
            check.lineWidth = bounds.width * 0.095
            check.lineCapStyle = .round
            check.lineJoinStyle = .round

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setStroke()
            check.stroke()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Daydo"
        return image
    }()
}
