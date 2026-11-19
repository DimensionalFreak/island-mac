# Mac island

The Mac version of the island: a black, borderless window that sits over the notch and blends into it, growing with a spring animation to show messages. On Macs without a notch it is a small black pill at the top centre. It only appears on the Mac's own screen.

- Swift + SwiftUI + Swift Package Manager. No Xcode. No web views.
- Built on GitHub's cloud Mac by `.github/workflows/mac-build.yml` (only when the owner says "build mac").
- How to install the result: `HOW-TO-INSTALL-MAC.md`.
- Reads the shared message format (`../shared/MESSAGES.md`), version 1, unchanged.
- Log file: `~/Library/Logs/Island/island.log`.

Files in `Sources/Island/`: `main.swift` (start), `AppDelegate.swift` (window placement, menu-bar item), `IslandPanel.swift` (the window), `IslandView.swift` (the shape and card), `IslandController.swift` (queue, priorities, timers, button replies), `Listener.swift` (messages from other apps), `Message.swift` (reads and checks messages), `ScreenInfo.swift` (finds the built-in screen and the notch), `Log.swift`.

`build-app.sh` makes `Island.app` and `Island-mac.zip` (it only runs on a Mac).
