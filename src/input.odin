package main

import "core:log"
import "core:time"

// NOTE(nawe) Not good right now, because I'm basically remapping SDL
// that already knows all this, but it will be good in the future when
// I handroll the platform code, and I will need a standardized event
// system for all platforms.
Key_Code :: enum u32 {
    UNDEFINED                = 0,

    K_ENTER                  = 0x0000000d,
    K_ESCAPE                 = 0x0000001b,
    K_BACKSPACE              = 0x00000008,
    K_TAB                    = 0x00000009,
    K_SPACE                  = 0x00000020,
    K_EXCLAIM                = 0x00000021,
    K_DBLAPOSTROPHE          = 0x00000022,
    K_HASH                   = 0x00000023,
    K_DOLLAR                 = 0x00000024,
    K_PERCENT                = 0x00000025,
    K_AMPERSAND              = 0x00000026,
    K_APOSTROPHE             = 0x00000027,
    K_LEFTPAREN              = 0x00000028,
    K_RIGHTPAREN             = 0x00000029,
    K_ASTERISK               = 0x0000002a,
    K_PLUS                   = 0x0000002b,
    K_COMMA                  = 0x0000002c,
    K_MINUS                  = 0x0000002d,
    K_PERIOD                 = 0x0000002e,
    K_SLASH                  = 0x0000002f,
    K_0                      = 0x00000030,
    K_1                      = 0x00000031,
    K_2                      = 0x00000032,
    K_3                      = 0x00000033,
    K_4                      = 0x00000034,
    K_5                      = 0x00000035,
    K_6                      = 0x00000036,
    K_7                      = 0x00000037,
    K_8                      = 0x00000038,
    K_9                      = 0x00000039,
    K_COLON                  = 0x0000003a,
    K_SEMICOLON              = 0x0000003b,
    K_LESS                   = 0x0000003c,
    K_EQUALS                 = 0x0000003d,
    K_GREATER                = 0x0000003e,
    K_QUESTION               = 0x0000003f,
    K_AT                     = 0x00000040,
    K_LEFTBRACKET            = 0x0000005b,
    K_BACKSLASH              = 0x0000005c,
    K_RIGHTBRACKET           = 0x0000005d,
    K_CARET                  = 0x0000005e,
    K_UNDERSCORE             = 0x0000005f,
    K_GRAVE                  = 0x00000060,
    K_A                      = 0x00000061,
    K_B                      = 0x00000062,
    K_C                      = 0x00000063,
    K_D                      = 0x00000064,
    K_E                      = 0x00000065,
    K_F                      = 0x00000066,
    K_G                      = 0x00000067,
    K_H                      = 0x00000068,
    K_I                      = 0x00000069,
    K_J                      = 0x0000006a,
    K_K                      = 0x0000006b,
    K_L                      = 0x0000006c,
    K_M                      = 0x0000006d,
    K_N                      = 0x0000006e,
    K_O                      = 0x0000006f,
    K_P                      = 0x00000070,
    K_Q                      = 0x00000071,
    K_R                      = 0x00000072,
    K_S                      = 0x00000073,
    K_T                      = 0x00000074,
    K_U                      = 0x00000075,
    K_V                      = 0x00000076,
    K_W                      = 0x00000077,
    K_X                      = 0x00000078,
    K_Y                      = 0x00000079,
    K_Z                      = 0x0000007a,
    K_LEFTBRACE              = 0x0000007b,
    K_PIPE                   = 0x0000007c,
    K_RIGHTBRACE             = 0x0000007d,
    K_TILDE                  = 0x0000007e,
    K_DELETE                 = 0x0000007f,
    K_PLUSMINUS              = 0x000000b1,
    K_CAPSLOCK               = 0x40000039,
    K_F1                     = 0x4000003a,
    K_F2                     = 0x4000003b,
    K_F3                     = 0x4000003c,
    K_F4                     = 0x4000003d,
    K_F5                     = 0x4000003e,
    K_F6                     = 0x4000003f,
    K_F7                     = 0x40000040,
    K_F8                     = 0x40000041,
    K_F9                     = 0x40000042,
    K_F10                    = 0x40000043,
    K_F11                    = 0x40000044,
    K_F12                    = 0x40000045,
    K_PRINTSCREEN            = 0x40000046,
    K_SCROLLLOCK             = 0x40000047,
    K_PAUSE                  = 0x40000048,
    K_INSERT                 = 0x40000049,
    K_HOME                   = 0x4000004a,
    K_PAGEUP                 = 0x4000004b,
    K_END                    = 0x4000004d,
    K_PAGEDOWN               = 0x4000004e,
    K_RIGHT                  = 0x4000004f,
    K_LEFT                   = 0x40000050,
    K_DOWN                   = 0x40000051,
    K_UP                     = 0x40000052,
    K_NUMLOCKCLEAR           = 0x40000053,
    K_KP_DIVIDE              = 0x40000054,
    K_KP_MULTIPLY            = 0x40000055,
    K_KP_MINUS               = 0x40000056,
    K_KP_PLUS                = 0x40000057,
    K_KP_ENTER               = 0x40000058,
    K_KP_1                   = 0x40000059,
    K_KP_2                   = 0x4000005a,
    K_KP_3                   = 0x4000005b,
    K_KP_4                   = 0x4000005c,
    K_KP_5                   = 0x4000005d,
    K_KP_6                   = 0x4000005e,
    K_KP_7                   = 0x4000005f,
    K_KP_8                   = 0x40000060,
    K_KP_9                   = 0x40000061,
    K_KP_0                   = 0x40000062,
    K_KP_PERIOD              = 0x40000063,
    K_APPLICATION            = 0x40000065,
    K_POWER                  = 0x40000066,
    K_KP_EQUALS              = 0x40000067,
    K_F13                    = 0x40000068,
    K_F14                    = 0x40000069,
    K_F15                    = 0x4000006a,
    K_F16                    = 0x4000006b,
    K_F17                    = 0x4000006c,
    K_F18                    = 0x4000006d,
    K_F19                    = 0x4000006e,
    K_F20                    = 0x4000006f,
    K_F21                    = 0x40000070,
    K_F22                    = 0x40000071,
    K_F23                    = 0x40000072,
    K_F24                    = 0x40000073,
    K_EXECUTE                = 0x40000074,
    K_HELP                   = 0x40000075,
    K_MENU                   = 0x40000076,
    K_SELECT                 = 0x40000077,
    K_STOP                   = 0x40000078,
    K_AGAIN                  = 0x40000079,
    K_UNDO                   = 0x4000007a,
    K_CUT                    = 0x4000007b,
    K_COPY                   = 0x4000007c,
    K_PASTE                  = 0x4000007d,
    K_FIND                   = 0x4000007e,
    K_MUTE                   = 0x4000007f,
    K_VOLUMEUP               = 0x40000080,
    K_VOLUMEDOWN             = 0x40000081,
    K_KP_COMMA               = 0x40000085,
    K_KP_EQUALSAS400         = 0x40000086,
    K_ALTERASE               = 0x40000099,
    K_SYSREQ                 = 0x4000009a,
    K_CANCEL                 = 0x4000009b,
    K_CLEAR                  = 0x4000009c,
    K_PRIOR                  = 0x4000009d,
    K_RETURN2                = 0x4000009e,
    K_SEPARATOR              = 0x4000009f,
    K_OUT                    = 0x400000a0,
    K_OPER                   = 0x400000a1,
    K_CLEARAGAIN             = 0x400000a2,
    K_CRSEL                  = 0x400000a3,
    K_EXSEL                  = 0x400000a4,
    K_KP_00                  = 0x400000b0,
    K_KP_000                 = 0x400000b1,
    K_THOUSANDSSEPARATOR     = 0x400000b2,
    K_DECIMALSEPARATOR       = 0x400000b3,
    K_CURRENCYUNIT           = 0x400000b4,
    K_CURRENCYSUBUNIT        = 0x400000b5,
    K_KP_LEFTPAREN           = 0x400000b6,
    K_KP_RIGHTPAREN          = 0x400000b7,
    K_KP_LEFTBRACE           = 0x400000b8,
    K_KP_RIGHTBRACE          = 0x400000b9,
    K_KP_TAB                 = 0x400000ba,
    K_KP_BACKSPACE           = 0x400000bb,
    K_KP_A                   = 0x400000bc,
    K_KP_B                   = 0x400000bd,
    K_KP_C                   = 0x400000be,
    K_KP_D                   = 0x400000bf,
    K_KP_E                   = 0x400000c0,
    K_KP_F                   = 0x400000c1,
    K_KP_XOR                 = 0x400000c2,
    K_KP_POWER               = 0x400000c3,
    K_KP_PERCENT             = 0x400000c4,
    K_KP_LESS                = 0x400000c5,
    K_KP_GREATER             = 0x400000c6,
    K_KP_AMPERSAND           = 0x400000c7,
    K_KP_DBLAMPERSAND        = 0x400000c8,
    K_KP_VERTICALBAR         = 0x400000c9,
    K_KP_DBLVERTICALBAR      = 0x400000ca,
    K_KP_COLON               = 0x400000cb,
    K_KP_HASH                = 0x400000cc,
    K_KP_SPACE               = 0x400000cd,
    K_KP_AT                  = 0x400000ce,
    K_KP_EXCLAM              = 0x400000cf,
    K_KP_MEMSTORE            = 0x400000d0,
    K_KP_MEMRECALL           = 0x400000d1,
    K_KP_MEMCLEAR            = 0x400000d2,
    K_KP_MEMADD              = 0x400000d3,
    K_KP_MEMSUBTRACT         = 0x400000d4,
    K_KP_MEMMULTIPLY         = 0x400000d5,
    K_KP_MEMDIVIDE           = 0x400000d6,
    K_KP_PLUSMINUS           = 0x400000d7,
    K_KP_CLEAR               = 0x400000d8,
    K_KP_CLEARENTRY          = 0x400000d9,
    K_KP_BINARY              = 0x400000da,
    K_KP_OCTAL               = 0x400000db,
    K_KP_DECIMAL             = 0x400000dc,
    K_KP_HEXADECIMAL         = 0x400000dd,
    K_LCTRL                  = 0x400000e0,
    K_LSHIFT                 = 0x400000e1,
    K_LALT                   = 0x400000e2,
    K_LGUI                   = 0x400000e3,
    K_RCTRL                  = 0x400000e4,
    K_RSHIFT                 = 0x400000e5,
    K_RALT                   = 0x400000e6,
    K_RGUI                   = 0x400000e7,
    K_MODE                   = 0x40000101,
    K_SLEEP                  = 0x40000102,
    K_WAKE                   = 0x40000103,
    K_CHANNEL_INCREMENT      = 0x40000104,
    K_CHANNEL_DECREMENT      = 0x40000105,
    K_MEDIA_PLAY             = 0x40000106,
    K_MEDIA_PAUSE            = 0x40000107,
    K_MEDIA_RECORD           = 0x40000108,
    K_MEDIA_FAST_FORWARD     = 0x40000109,
    K_MEDIA_REWIND           = 0x4000010a,
    K_MEDIA_NEXT_TRACK       = 0x4000010b,
    K_MEDIA_PREVIOUS_TRACK   = 0x4000010c,
    K_MEDIA_STOP             = 0x4000010d,
    K_MEDIA_EJECT            = 0x4000010e,
    K_MEDIA_PLAY_PAUSE       = 0x4000010f,
    K_MEDIA_SELECT           = 0x40000110,
    K_AC_NEW                 = 0x40000111,
    K_AC_OPEN                = 0x40000112,
    K_AC_CLOSE               = 0x40000113,
    K_AC_EXIT                = 0x40000114,
    K_AC_SAVE                = 0x40000115,
    K_AC_PRINT               = 0x40000116,
    K_AC_PROPERTIES          = 0x40000117,
    K_AC_SEARCH              = 0x40000118,
    K_AC_HOME                = 0x40000119,
    K_AC_BACK                = 0x4000011a,
    K_AC_FORWARD             = 0x4000011b,
    K_AC_STOP                = 0x4000011c,
    K_AC_REFRESH             = 0x4000011d,
    K_AC_BOOKMARKS           = 0x4000011e,
    K_SOFTLEFT               = 0x4000011f,
    K_SOFTRIGHT              = 0x40000120,
    K_CALL                   = 0x40000121,
    K_ENDCALL                = 0x40000122,
    K_LEFT_TAB               = 0x20000001,
    K_LEVEL5_SHIFT           = 0x20000002,
    K_MULTI_KEY_COMPOSE      = 0x20000003,
    K_LMETA                  = 0x20000004,
    K_RMETA                  = 0x20000005,
    K_LHYPER                 = 0x20000006,
    K_RHYPER                 = 0x20000007,
}

Mouse_Button :: enum u8 {
    Left    = 0,
    Middle  = 1,
    Right   = 2,
    Extra_1 = 3,
    Extra_2 = 4,
}

Key_Mod :: enum u8 {
    Alt       = 0,
    Ctrl      = 1,
    Shift     = 2,
    Command   = 3,
    Super     = 4,
    Caps_Lock = 5,
}

Modifiers_Set :: bit_set[Key_Mod; u8]

Event :: struct {
    // Warns that this event wasn't handled properly, helpful during
    // development to make sure inputs are being accounted for.
    handled:   bool,
    timestamp: time.Tick,
    variant:   Event_Variant,
}

Event_Variant :: union {
    Event_Drop_File,
    Event_Keyboard,
    Event_Mouse,
    Event_Quit,
    Event_Window,
}

Event_Drop_File :: struct {
    filepath: string,
    data:     []byte,
}

Event_Keyboard :: struct {
    is_text_input: bool,
    // if 'is_text_input', check 'text', otherwise check 'key_pressed' or 'key_code'
    text:          string,
    key_pressed:   u32,
    key_code:      Key_Code,
    modifiers:     Modifiers_Set,
    repeat:        bool,
}

Event_Mouse :: struct {
    button_pressed: Mouse_Button,
    mouse_x:        i32,
    mouse_y:        i32,
    wheel_scroll:   i32,
}

Event_Quit :: struct {}

Event_Window :: struct {
    // active resizing, as in the user hasn't yet completed their resize
    resizing:         bool,
    moving:           bool,
    dpi_scale:        f32,
    window_height:    i32,
    window_width:     i32,
    window_focused:   bool,
}

input_key_code_to_string :: #force_inline proc(key_code: Key_Code) -> string {
    if key_code == .UNDEFINED do unreachable()
    return platform_key_name(u32(key_code))
}

input_update_and_prepare :: proc() {
    for &event in events_this_frame {
        switch v in event.variant {
        case Event_Drop_File:
            delete(v.filepath)
            delete(v.data)
        case Event_Keyboard:
            when ODIN_DEBUG {
                if !event.handled && !v.is_text_input {
                    if v.key_pressed >= 32 && v.key_pressed < 256 {
                        // NOTE(nawe) this was probably handled as text input
                        event.handled = true
                    }
                }
            }
        case Event_Mouse:
        case Event_Quit:
        case Event_Window:
        }

        when ODIN_DEBUG {
            if !event.handled {
                log.warnf("event wasn't handled properly {}", event)
            }
        }
    }

    clear(&events_this_frame)
}

input_register :: proc(variant: Event_Variant) {
    append(&events_this_frame, Event{
        timestamp = time.tick_now(),
        variant   = variant,
    })
}

input_destroy :: proc() {
    input_update_and_prepare()
    delete(events_this_frame)
}
