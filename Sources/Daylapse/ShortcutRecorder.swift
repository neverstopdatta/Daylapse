import AppKit
import Carbon
import SwiftUI

// Lets Settings ask the app delegate to re-register the global shortcut.
@MainActor
enum ShortcutRegistrar {
    static var apply: ((UInt32, UInt32) -> Bool)?
}

enum KeyNames {
    private static let names: [UInt32: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q",
        13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i",
        35: "p", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "n", 46: "m",
        47: ".", 49: " ", 50: "`",
    ]

    static func character(for keyCode: UInt32) -> String? { names[keyCode] }

    static func display(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        switch keyCode {
        case 49: text += "Space"
        default: text += character(for: keyCode)?.uppercased() ?? "Key \(keyCode)"
        }
        return text
    }

    static func menuModifierMask(_ carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
        return mask
    }
}

struct ShortcutRecorder: View {
    @Binding var shortcut: ShortcutSettings
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        HStack {
            Button(isRecording ? "Press shortcut…" : KeyNames.display(keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers)) {
                isRecording ? stopRecording() : startRecording()
            }
            Button("Reset") { apply(ShortcutSettings.default.keyCode, ShortcutSettings.default.carbonModifiers) }
                .disabled(shortcut == .default)
            if let message {
                Text(message).foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        message = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            var carbon: UInt32 = 0
            let flags = event.modifierFlags
            if flags.contains(.command) { carbon |= UInt32(cmdKey) }
            if flags.contains(.option) { carbon |= UInt32(optionKey) }
            if flags.contains(.control) { carbon |= UInt32(controlKey) }
            if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
            guard carbon & UInt32(cmdKey | optionKey | controlKey) != 0 else {
                NSSound.beep()
                return nil
            }
            let keyCode = UInt32(event.keyCode)
            stopRecording()
            apply(keyCode, carbon)
            return nil
        }
    }

    private func apply(_ keyCode: UInt32, _ carbon: UInt32) {
        if ShortcutRegistrar.apply?(keyCode, carbon) == true {
            shortcut = ShortcutSettings(keyCode: keyCode, carbonModifiers: carbon)
            message = nil
        } else {
            message = "Shortcut unavailable"
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
