import AppKit

// macOS has no public way to keep a window drawn during the trackpad swipe between desktops and
// full-screen apps. The video from the owner's Mac showed the island missing for a moment in the
// middle of that swipe. Apple's own menu bar and Dock avoid this by living in a special top-level
// "space". These are the macOS calls (not documented by Apple, used by many notch apps) that put
// our window in such a space. If a call is ever missing or changes, the island still works as before.

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSSpaceCreate")
func CGSSpaceCreate(_ connection: CGSConnectionID, _ unknown: Int, _ options: NSDictionary?) -> CGSSpaceID

@_silgen_name("CGSSpaceSetAbsoluteLevel")
func CGSSpaceSetAbsoluteLevel(_ connection: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)

@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ connection: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)

@_silgen_name("CGSShowSpaces")
func CGSShowSpaces(_ connection: CGSConnectionID, _ spaces: NSArray)

enum TopSpace {
    private static var spaceID: CGSSpaceID?

    /// Call once the window is on screen (it needs a real window number).
    static func add(_ window: NSWindow) {
        guard window.windowNumber > 0 else {
            Log.write("TopSpace: window has no number yet, skipped")
            return
        }
        let connection = CGSMainConnectionID()
        if spaceID == nil {
            let space = CGSSpaceCreate(connection, 0x1, nil)
            CGSSpaceSetAbsoluteLevel(connection, space, 2_147_483_647)
            CGSShowSpaces(connection, [NSNumber(value: space)] as NSArray)
            spaceID = space
        }
        guard let space = spaceID else { return }
        CGSAddWindowsToSpaces(connection, [NSNumber(value: window.windowNumber)] as NSArray,
                              [NSNumber(value: space)] as NSArray)
        Log.write("TopSpace: island window \(window.windowNumber) added to top space \(space)")
    }
}
