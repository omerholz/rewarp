import AppKit
import CGhosttyVT

/// macOS virtual key codes to the library's physical keys.
let keyCodeMap: [UInt16: GhosttyKey] = [
    0: GHOSTTY_KEY_A, 1: GHOSTTY_KEY_S, 2: GHOSTTY_KEY_D, 3: GHOSTTY_KEY_F, 4: GHOSTTY_KEY_H,
    5: GHOSTTY_KEY_G, 6: GHOSTTY_KEY_Z, 7: GHOSTTY_KEY_X, 8: GHOSTTY_KEY_C, 9: GHOSTTY_KEY_V,
    11: GHOSTTY_KEY_B, 12: GHOSTTY_KEY_Q, 13: GHOSTTY_KEY_W, 14: GHOSTTY_KEY_E, 15: GHOSTTY_KEY_R,
    16: GHOSTTY_KEY_Y, 17: GHOSTTY_KEY_T, 18: GHOSTTY_KEY_DIGIT_1, 19: GHOSTTY_KEY_DIGIT_2,
    20: GHOSTTY_KEY_DIGIT_3, 21: GHOSTTY_KEY_DIGIT_4, 22: GHOSTTY_KEY_DIGIT_6, 23: GHOSTTY_KEY_DIGIT_5,
    24: GHOSTTY_KEY_EQUAL, 25: GHOSTTY_KEY_DIGIT_9, 26: GHOSTTY_KEY_DIGIT_7, 27: GHOSTTY_KEY_MINUS,
    28: GHOSTTY_KEY_DIGIT_8, 29: GHOSTTY_KEY_DIGIT_0, 30: GHOSTTY_KEY_BRACKET_RIGHT, 31: GHOSTTY_KEY_O,
    32: GHOSTTY_KEY_U, 33: GHOSTTY_KEY_BRACKET_LEFT, 34: GHOSTTY_KEY_I, 35: GHOSTTY_KEY_P,
    36: GHOSTTY_KEY_ENTER, 37: GHOSTTY_KEY_L, 38: GHOSTTY_KEY_J, 39: GHOSTTY_KEY_QUOTE, 40: GHOSTTY_KEY_K,
    41: GHOSTTY_KEY_SEMICOLON, 42: GHOSTTY_KEY_BACKSLASH, 43: GHOSTTY_KEY_COMMA, 44: GHOSTTY_KEY_SLASH,
    45: GHOSTTY_KEY_N, 46: GHOSTTY_KEY_M, 47: GHOSTTY_KEY_PERIOD, 48: GHOSTTY_KEY_TAB, 49: GHOSTTY_KEY_SPACE,
    50: GHOSTTY_KEY_BACKQUOTE, 51: GHOSTTY_KEY_BACKSPACE, 53: GHOSTTY_KEY_ESCAPE,
    54: GHOSTTY_KEY_META_RIGHT, 55: GHOSTTY_KEY_META_LEFT, 56: GHOSTTY_KEY_SHIFT_LEFT,
    57: GHOSTTY_KEY_CAPS_LOCK, 58: GHOSTTY_KEY_ALT_LEFT, 59: GHOSTTY_KEY_CONTROL_LEFT,
    60: GHOSTTY_KEY_SHIFT_RIGHT, 61: GHOSTTY_KEY_ALT_RIGHT, 62: GHOSTTY_KEY_CONTROL_RIGHT, 63: GHOSTTY_KEY_FN,
    64: GHOSTTY_KEY_F17, 65: GHOSTTY_KEY_NUMPAD_DECIMAL, 67: GHOSTTY_KEY_NUMPAD_MULTIPLY,
    69: GHOSTTY_KEY_NUMPAD_ADD, 71: GHOSTTY_KEY_NUMPAD_CLEAR, 75: GHOSTTY_KEY_NUMPAD_DIVIDE,
    76: GHOSTTY_KEY_NUMPAD_ENTER, 78: GHOSTTY_KEY_NUMPAD_SUBTRACT, 79: GHOSTTY_KEY_F18, 80: GHOSTTY_KEY_F19,
    81: GHOSTTY_KEY_NUMPAD_EQUAL, 82: GHOSTTY_KEY_NUMPAD_0, 83: GHOSTTY_KEY_NUMPAD_1, 84: GHOSTTY_KEY_NUMPAD_2,
    85: GHOSTTY_KEY_NUMPAD_3, 86: GHOSTTY_KEY_NUMPAD_4, 87: GHOSTTY_KEY_NUMPAD_5, 88: GHOSTTY_KEY_NUMPAD_6,
    89: GHOSTTY_KEY_NUMPAD_7, 90: GHOSTTY_KEY_F20, 91: GHOSTTY_KEY_NUMPAD_8, 92: GHOSTTY_KEY_NUMPAD_9,
    96: GHOSTTY_KEY_F5, 97: GHOSTTY_KEY_F6, 98: GHOSTTY_KEY_F7, 99: GHOSTTY_KEY_F3, 100: GHOSTTY_KEY_F8,
    101: GHOSTTY_KEY_F9, 103: GHOSTTY_KEY_F11, 105: GHOSTTY_KEY_F13, 106: GHOSTTY_KEY_F16, 107: GHOSTTY_KEY_F14,
    109: GHOSTTY_KEY_F10, 111: GHOSTTY_KEY_F12, 113: GHOSTTY_KEY_F15, 114: GHOSTTY_KEY_INSERT,
    115: GHOSTTY_KEY_HOME, 116: GHOSTTY_KEY_PAGE_UP, 117: GHOSTTY_KEY_DELETE, 118: GHOSTTY_KEY_F4,
    119: GHOSTTY_KEY_END, 120: GHOSTTY_KEY_F2, 121: GHOSTTY_KEY_PAGE_DOWN, 122: GHOSTTY_KEY_F1,
    123: GHOSTTY_KEY_ARROW_LEFT, 124: GHOSTTY_KEY_ARROW_RIGHT, 125: GHOSTTY_KEY_ARROW_DOWN, 126: GHOSTTY_KEY_ARROW_UP,
]

func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> GhosttyMods {
    var mods: UInt16 = 0
    if flags.contains(.shift) { mods |= UInt16(GHOSTTY_MODS_SHIFT) }
    if flags.contains(.control) { mods |= UInt16(GHOSTTY_MODS_CTRL) }
    if flags.contains(.option) { mods |= UInt16(GHOSTTY_MODS_ALT) }
    if flags.contains(.command) { mods |= UInt16(GHOSTTY_MODS_SUPER) }
    if flags.contains(.capsLock) { mods |= UInt16(GHOSTTY_MODS_CAPS_LOCK) }
    return mods
}

/// Encodes keys for whatever modes the running program has asked for.
final class KeyEncoder {
    private let encoder: GhosttyKeyEncoder
    private let event: GhosttyKeyEvent

    init() {
        var encoder: GhosttyKeyEncoder?
        var event: GhosttyKeyEvent?
        guard ghostty_key_encoder_new(nil, &encoder) == GHOSTTY_SUCCESS,
              ghostty_key_event_new(nil, &event) == GHOSTTY_SUCCESS,
              let encoder, let event else {
            fatalError("could not create the key encoder")
        }
        self.encoder = encoder
        self.event = event
    }

    deinit {
        ghostty_key_event_free(event)
        ghostty_key_encoder_free(encoder)
    }

    /// Must run under the session lock.
    func syncModes(from terminal: GhosttyTerminal) {
        ghostty_key_encoder_setopt_from_terminal(encoder, terminal)
    }

    func encode(_ nsEvent: NSEvent, action: GhosttyKeyAction, text: String) -> [UInt8] {
        let mods = ghosttyMods(nsEvent.modifierFlags)
        ghostty_key_event_set_action(event, action)
        ghostty_key_event_set_key(event, keyCodeMap[nsEvent.keyCode] ?? GHOSTTY_KEY_UNIDENTIFIED)
        ghostty_key_event_set_mods(event, mods)
        ghostty_key_event_set_composing(event, false)

        // Modifiers that went into producing the text are spent, so that shift+a
        // arrives as "A" rather than as a modified key in kitty mode.
        var consumed: UInt16 = 0
        if !text.isEmpty {
            consumed = mods & UInt16(GHOSTTY_MODS_SHIFT | GHOSTTY_MODS_ALT)
        }
        ghostty_key_event_set_consumed_mods(event, consumed)

        let unshifted = nsEvent.characters(byApplyingModifiers: [])?.unicodeScalars.first?.value ?? 0
        ghostty_key_event_set_unshifted_codepoint(event, unshifted)

        let bytes = Array(text.utf8)
        // An input method can commit far more text than one key produces.
        var output = [CChar](repeating: 0, count: 128 + bytes.count)
        var written = 0
        let result: GhosttyResult = bytes.withUnsafeBufferPointer { utf8 in
            let pointer = utf8.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) }
            ghostty_key_event_set_utf8(event, pointer, utf8.count)
            return ghostty_key_encoder_encode(encoder, event, &output, output.count, &written)
        }
        ghostty_key_event_set_utf8(event, nil, 0)
        guard result == GHOSTTY_SUCCESS else { return [] }
        return output[..<written].map { UInt8(bitPattern: $0) }
    }
}

/// Encodes mouse events for programs that asked to receive them.
final class MouseEncoder {
    private let encoder: GhosttyMouseEncoder
    private let event: GhosttyMouseEvent

    init() {
        var encoder: GhosttyMouseEncoder?
        var event: GhosttyMouseEvent?
        guard ghostty_mouse_encoder_new(nil, &encoder) == GHOSTTY_SUCCESS,
              ghostty_mouse_event_new(nil, &event) == GHOSTTY_SUCCESS,
              let encoder, let event else {
            fatalError("could not create the mouse encoder")
        }
        self.encoder = encoder
        self.event = event
    }

    deinit {
        ghostty_mouse_event_free(event)
        ghostty_mouse_encoder_free(encoder)
    }

    /// Must run under the session lock.
    func sync(from terminal: GhosttyTerminal, size: GhosttyMouseEncoderSize, anyButtonPressed: Bool) {
        ghostty_mouse_encoder_setopt_from_terminal(encoder, terminal)
        var size = size
        var pressed = anyButtonPressed
        _ = ghostty_mouse_encoder_setopt(encoder, GHOSTTY_MOUSE_ENCODER_OPT_SIZE, &size)
        _ = ghostty_mouse_encoder_setopt(encoder, GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED, &pressed)
    }

    func encode(action: GhosttyMouseAction, button: GhosttyMouseButton?, mods: GhosttyMods, x: Float, y: Float) -> [UInt8] {
        ghostty_mouse_event_set_action(event, action)
        if let button {
            ghostty_mouse_event_set_button(event, button)
        } else {
            ghostty_mouse_event_clear_button(event)
        }
        ghostty_mouse_event_set_mods(event, mods)
        ghostty_mouse_event_set_position(event, GhosttyMousePosition(x: x, y: y))
        var output = [CChar](repeating: 0, count: 128)
        var written = 0
        guard ghostty_mouse_encoder_encode(encoder, event, &output, output.count, &written) == GHOSTTY_SUCCESS else {
            return []
        }
        return output[..<written].map { UInt8(bitPattern: $0) }
    }
}
