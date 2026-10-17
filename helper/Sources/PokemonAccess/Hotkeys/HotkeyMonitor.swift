import Carbon
import Foundation
import PokemonAccessCore

/// Registers upstream's hotkeys as Carbon hot keys. The system delivers them
/// to this process and swallows them, so mGBA never sees the letters, and no
/// Accessibility permission is needed. Enabled only while mGBA is frontmost.
final class HotkeyMonitor {
    enum HotkeyError: Error {
        case handlerInstallFailed(OSStatus)
    }

    private static let signature: OSType = 0x504B_4143 // "PKAC"

    private let chords: [HotkeyChord]
    private let layout: KeyboardLayout
    private let onEvent: (HotkeyChord, Bool) -> Void
    private let log: FileLog
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private(set) var isEnabled = false

    init(chords: [HotkeyChord], layout: KeyboardLayout, log: FileLog, onEvent: @escaping (HotkeyChord, Bool) -> Void) {
        self.chords = chords
        self.layout = layout
        self.log = log
        self.onEvent = onEvent
    }

    func enable() throws {
        guard !isEnabled else { return }
        if handler == nil {
            try installHandler()
        }
        for (index, chord) in chords.enumerated() {
            guard let keyCode = layout.keyCode(for: chord.key) else {
                log.error("no key code for hotkey \(chord.name) in the current keyboard layout")
                continue
            }
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let modifiers: UInt32 = chord.shift ? UInt32(shiftKey) : 0
            let status = RegisterEventHotKey(UInt32(keyCode), modifiers, id, GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                registrations.append(reference)
            } else {
                log.error("registering hotkey \(chord.name) failed with status \(status)")
            }
        }
        isEnabled = true
        log.info("hotkeys enabled (\(registrations.count) of \(chords.count))")
    }

    func disable() {
        guard isEnabled else { return }
        for reference in registrations {
            UnregisterEventHotKey(reference)
        }
        registrations = []
        isEnabled = false
        log.info("hotkeys disabled")
    }

    private func installHandler() throws {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            monitor.dispatch(id: hotKeyID, down: GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr {
            throw HotkeyError.handlerInstallFailed(status)
        }
    }

    private func dispatch(id: EventHotKeyID, down: Bool) {
        guard id.signature == Self.signature, id.id >= 1, Int(id.id) <= chords.count else { return }
        onEvent(chords[Int(id.id) - 1], down)
    }
}
