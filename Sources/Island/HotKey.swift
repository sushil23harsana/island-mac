import Carbon.HIToolbox

/// A system-wide keyboard shortcut using Carbon's RegisterEventHotKey.
/// Unlike global NSEvent monitors, this needs no Accessibility permission.
final class HotKey {
    nonisolated(unsafe) private static var nextID: UInt32 = 1

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    /// - Parameters:
    ///   - keyCode: a `kVK_*` virtual key code.
    ///   - modifiers: Carbon modifier mask, e.g. `optionKey`, `cmdKey | shiftKey`.
    init?(keyCode: Int, modifiers: Int, action: @escaping @MainActor () -> Void) {
        self.action = action
        id = HotKey.nextID
        HotKey.nextID += 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()

            // Every handler sees every hotkey press; only react to our own.
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }

            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &eventType, userData, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x49534C44) /* 'ISLD' */, id: id)
        let registerStatus = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)

        guard installStatus == noErr, registerStatus == noErr else { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
