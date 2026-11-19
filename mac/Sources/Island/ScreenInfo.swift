import AppKit

/// Where the island sits and how big it is at rest.
struct ScreenGeometry {
    var hasNotch: Bool
    /// Width and height of the island at rest: the notch itself, or a small pill.
    var restWidth: CGFloat
    var restHeight: CGFloat
    /// Height of the notch area (0 without a notch); card content starts below it.
    var topInset: CGFloat
    var screenFrame: CGRect

    static let fallback = ScreenGeometry(hasNotch: false, restWidth: 140, restHeight: 22, topInset: 0,
                                         screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
}

enum ScreenInfo {
    /// The Mac's own display (never an external monitor). nil if only external screens are left (lid closed).
    static func builtInScreen() -> NSScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[key] as? NSNumber,
               CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0 {
                return screen
            }
        }
        return nil
    }

    static func geometry(for screen: NSScreen) -> ScreenGeometry {
        let frame = screen.frame
        let inset = screen.safeAreaInsets.top
        if inset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let notchWidth = frame.width - left.width - right.width
            if notchWidth > 20 {
                return ScreenGeometry(hasNotch: true, restWidth: notchWidth, restHeight: inset,
                                      topInset: inset, screenFrame: frame)
            }
        }
        // No notch: draw a notch-shaped "lip" hanging from the top edge, like a real one (a little thinner than first tried).
        return ScreenGeometry(hasNotch: false, restWidth: 140, restHeight: 22, topInset: 0, screenFrame: frame)
    }
}
