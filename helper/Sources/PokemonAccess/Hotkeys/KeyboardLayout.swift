import Carbon
import Foundation
import PokemonAccessCore

/// Maps characters to virtual key codes for the keyboard layout in use, so
/// that pressing the key that prints "t" triggers upstream's T command on
/// any layout. Falls back to the ANSI US table for characters the layout
/// does not produce.
struct KeyboardLayout {
    private let codes: [Character: UInt16]

    init(codes: [Character: UInt16]) {
        self.codes = codes
    }

    static func current() -> KeyboardLayout {
        var codes: [Character: UInt16] = [:]
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
                let keyboardType = UInt32(LMGetKbdType())
                for code in 0..<128 {
                    var deadKeyState: UInt32 = 0
                    var characters = [UniChar](repeating: 0, count: 4)
                    var length = 0
                    let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0, keyboardType,
                                                UInt32(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                                                characters.count, &length, &characters)
                    guard status == noErr, length == 1, let scalar = Unicode.Scalar(characters[0]),
                          let upper = Character(scalar).uppercased().first else { continue }
                    if codes[upper] == nil {
                        codes[upper] = UInt16(code)
                    }
                }
            }
        }
        return KeyboardLayout(codes: codes)
    }

    func keyCode(for character: Character) -> UInt16? {
        guard let upper = character.uppercased().first else { return nil }
        return codes[upper] ?? AnsiKeyCodes.keyCode(for: upper)
    }
}
