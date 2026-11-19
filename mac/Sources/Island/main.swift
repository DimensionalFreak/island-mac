import AppKit

// No Dock icon, no app-switcher entry: Info.plist sets LSUIElement and this makes it explicit.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
