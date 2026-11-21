import Carbon.HIToolbox
import Foundation

/// TEMPORARY: one global keyboard shortcut (Control + Option + S) used to step through the island's
/// sizes while testing. macOS lets an app register a hot key without any special permission.
/// Remove this file, and the lines that use it in AppDelegate, once the sizes are approved.
final class HotKey {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(keyCode: UInt32, modifiers: UInt32) {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData = userData else { return noErr }
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress?() }
            return noErr
        }, 1, &spec, pointer, &handlerRef)
        guard installed == noErr else {
            Log.write("HotKey: could not install the handler (\(installed))")
            return
        }
        let id = EventHotKeyID(signature: OSType(0x49534C44), id: 1)
        let registered = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if registered != noErr { Log.write("HotKey: could not register Control+Option+S (\(registered))") }
    }
}
