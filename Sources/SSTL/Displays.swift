import AppKit
import CoreGraphics

// Display identity that survives primary-display changes and reconnects.
// The numeric display ID can change; the display's UUID belongs to the physical screen.
enum Displays {
    struct Option: Hashable {
        let key: String
        let name: String
    }

    // 8 hex characters hashed from the whole UUID (FNV-1a).
    static func key(for id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) as String? else { return String(id, radix: 16) }
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return String(format: "%08x", hash)
    }

    // The built-in screen keeps the plain file name; every other display gets its own stable suffix.
    static func fileSuffix(for id: CGDirectDisplayID) -> String {
        CGDisplayIsBuiltin(id) != 0 ? "" : "_d" + key(for: id)
    }

    // Currently connected displays, for the picker.
    static func connected() -> [Option] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return Option(key: key(for: id), name: screen.localizedName)
        }
    }

    // `setting` is "all", "main" (whichever display is primary now) or a display key.
    static func matches(_ setting: String, id: CGDirectDisplayID) -> Bool {
        switch setting {
        case "all": true
        case "main": id == CGMainDisplayID()
        default: key(for: id) == setting
        }
    }
}
