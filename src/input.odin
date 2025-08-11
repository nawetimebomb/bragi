package main

import "core:log"
import "core:time"

// NOTE(nawe) Not good right now, because I'm basically remapping SDL
// that already knows all this, but it will be good in the future when
// I handroll the platform code, and I will need a standardized event
// system for all platforms.

Key_Code :: enum u32 {
    Undefined   = 0,

    // Following page 0x07 (USB keyboard)
    // https://www.usb.org/sites/default/files/documents/hut1_12v2.pdf

    // * Alphanumerics and symbols are in rune_pressed
    // * Mod keys are in modifiers bit set.

    Enter       = 40,
    Escape      = 41,
    Backspace   = 42,
    Tab         = 43,
    Spacebar    = 44,
    Minus       = 45,
    Equals      = 46,

    F1          = 58,
    F2          = 59,
    F3          = 60,
    F4          = 61,
    F5          = 62,
    F6          = 63,
    F7          = 64,
    F8          = 65,
    F9          = 66,
    F10         = 67,
    F11         = 68,
    F12         = 69,

    Home        = 74,
    Page_Up     = 75,
    Delete      = 76,
    End         = 77,
    Page_Down   = 78,
    Arrow_Right = 79,
    Arrow_Left  = 80,
    Arrow_Down  = 81,
    Arrow_Up    = 82,

    F13         = 104,
    F14         = 105,
    F15         = 106,
    F16         = 107,
    F17         = 108,
    F18         = 109,
    F19         = 110,
    F20         = 111,
    F21         = 112,
    F22         = 113,
    F23         = 114,
    F24         = 115,
}

Key_Mod :: enum u8 {
    Alt       = 0,
    Ctrl      = 1,
    Shift     = 2,
    Super     = 3,
    Cmd       = 4,
    Caps_Lock = 5,
}

Event :: struct {
    // Warn that this event wasn't handled properly, helpful during
    // development to make sure inputs are being accounted for.
    handled: bool,
    time:    time.Tick,
    variant: Event_Variant,
}

Event_Variant :: union {
    Event_Keyboard,
    Event_Mouse,
    Event_Quit,
    Event_Window,
}

Event_Keyboard :: struct {
    is_text_input: bool,
    // if is_text_input, the rune pressed should be treated as text
    // input event, otherwise, the key was pressed as part of a
    // regular keyboard event.
    rune_pressed:  rune,
    // for keys that are not runes.
    key_pressed:   Key_Code,
    modifiers:     bit_set[Key_Mod; u8],
    repeat:        bool,
}

Event_Mouse :: struct {
    mouse_x:       i32,
    mouse_y:       i32,
    wheel_y:       i32,
    wheel_pressed: bool,
}

Event_Quit :: struct {}

Event_Window :: struct {
    // active resizing, as in the user hasn't yet completed their resize
    resizing:       bool,
    moving:         bool,
    window_x:       i32,
    window_y:       i32,
    window_height:  i32,
    window_width:   i32,
    window_focused: bool,
}

events_this_frame: [dynamic]Event

input_update_and_prepare :: proc() {
    for event in events_this_frame {
        if !event.handled {
            log.warnf("event wasn't handled properly {}", event)
        }
    }

    clear(&events_this_frame)
}

input_register :: proc(variant: Event_Variant) {
    append(&events_this_frame, Event{
        time    = time.tick_now(),
        variant = variant,
    })
}

input_destroy :: proc() {
    input_update_and_prepare()
    delete(events_this_frame)
}
