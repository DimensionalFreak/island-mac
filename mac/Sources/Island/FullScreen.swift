import AppKit
import CoreGraphics

/// Tells whether another app is in TRUE full screen on the built-in display (a video, a game, or an
/// app that went full screen with the green button). A window that is only maximized does not count:
/// it leaves the menu bar showing and does not start at the very top of the screen.
///
/// Two signals, either one is enough:
///  1. an ordinary window of another app that covers the whole display, from its very top edge;
///  2. the menu bar is gone. Macs with a notch can run full-screen apps just below the notch, where
///     signal 1 does not match, but the menu bar is hidden there too. Signal 2 is only trusted after
///     this check has seen the menu bar at least once, so a macOS change can never hide the island forever.
enum FullScreenCheck {
    private static var menuBarSeen = false

    static func isFullScreen(on screen: NSScreen) -> Bool {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return false }
        let display = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        var menuBarVisible = false
        var coversDisplay = false

        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  let boundsInfo = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else { continue }
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let pid = window[kCGWindowOwnerPID as String] as? Int ?? -1
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1

            // The menu bar: a Window Server window on layer 24 along the top of the display.
            if layer == 24, owner == "Window Server",
               rect.width >= display.width - 1,
               rect.minY >= display.minY - 0.5, rect.minY < display.minY + 5 {
                menuBarVisible = true
            }
            // A normal window of another app covering the whole display from its top edge.
            if layer == 0, pid != myPID, alpha > 0.01,
               rect.width >= display.width - 1, rect.height >= display.height - 1,
               abs(rect.minY - display.minY) < 1 {
                coversDisplay = true
            }
        }
        if menuBarVisible { menuBarSeen = true }
        return coversDisplay || (menuBarSeen && !menuBarVisible)
    }
}
