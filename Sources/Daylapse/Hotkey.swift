import Carbon
import Foundation

final class Hotkey {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr && hotKeyID.id == 1 {
                    Unmanaged<Hotkey>.fromOpaque(userData).takeUnretainedValue().action()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
        guard installStatus == noErr else { return false }

        let identifier = EventHotKeyID(signature: OSType(0x444C5053), id: 1)
        let status = RegisterEventHotKey(keyCode, carbonModifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            eventHandler = nil
            hotKey = nil
            return false
        }
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
    }

    deinit { unregister() }
}
