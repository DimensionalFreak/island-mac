import AppKit
import SwiftUI

/// The island's window: borderless, see-through, above the menu bar and every app,
/// on every desktop, and it can never take the keyboard focus.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        // The very top window layer (the one macOS uses to cover the whole screen).
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // The window is only as big as the island (plus a little room), so it can listen to the mouse
        // (hover, click) without getting in the way of anything else.
        ignoresMouseEvents = false
    }
}

/// Lets a button work on the very first click even though the window never becomes active,
/// and reports when the mouse enters or leaves the island's window (for hover).
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = hoverArea { removeTrackingArea(old) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}
