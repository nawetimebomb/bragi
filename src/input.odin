package main

import "core:log"
import "core:reflect"
import "core:time"

// NOTE(nawe) Not good right now, because I'm basically remapping SDL
// that already knows all this, but it will be good in the future when
// I handroll the platform code, and I will need a standardized event
// system for all platforms.
Key_Code :: enum u32 {
    Undefined     = 0,

    // Following page 0x07 (USB keyboard)
    // https://www.usb.org/sites/default/files/documents/hut1_12v2.pdf

    A             = 4,
    B             = 5,
    C             = 6,
    D             = 7,
    E             = 8,
    F             = 9,
    G             = 10,
    H             = 11,
    I             = 12,
    J             = 13,
    K             = 14,
    L             = 15,
    M             = 16,
    N             = 17,
    O             = 18,
    P             = 19,
    Q             = 20,
    R             = 21,
    S             = 22,
    T             = 23,
    U             = 24,
    V             = 25,
    W             = 26,
    X             = 27,
    Y             = 28,
    Z             = 29,
    Num_1         = 30,
    Num_2         = 31,
    Num_3         = 32,
    Num_4         = 33,
    Num_5         = 34,
    Num_6         = 35,
    Num_7         = 36,
    Num_8         = 37,
    Num_9         = 38,
    Num_0         = 39,
    Enter         = 40,
    Escape        = 41,
    Backspace     = 42,
    Tab           = 43,
    Spacebar      = 44,
    Minus         = 45,
    Equal         = 46,
    Left_Bracket  = 47,
    Right_Bracket = 48,
    Backslash     = 49,
    Semicolon     = 51,
    Apostrophe    = 52,
    Grave         = 53,
    Comma         = 54,
    Period        = 55,
    Slash         = 56,
    Capslock      = 57,
    F1            = 58,
    F2            = 59,
    F3            = 60,
    F4            = 61,
    F5            = 62,
    F6            = 63,
    F7            = 64,
    F8            = 65,
    F9            = 66,
    F10           = 67,
    F11           = 68,
    F12           = 69,

    Insert        = 73,
    Home          = 74,
    Page_Up       = 75,
    Delete        = 76,
    End           = 77,
    Page_Down     = 78,
    Arrow_Right   = 79,
    Arrow_Left    = 80,
    Arrow_Down    = 81,
    Arrow_Up      = 82,

    F13           = 104,
    F14           = 105,
    F15           = 106,
    F16           = 107,
    F17           = 108,
    F18           = 109,
    F19           = 110,
    F20           = 111,
    F21           = 112,
    F22           = 113,
    F23           = 114,
    F24           = 115,
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
    // Warn that this event wasn't handled properly, helpful during
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
    // if 'is_text_input', check 'text', otherwise check 'key_pressed'
    text:          string,
    key_pressed:   Key_Code,
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
    if key_code == .Undefined do unreachable()
    return reflect.enum_string(key_code)
}

input_update_and_prepare :: proc() {
    for event in events_this_frame {
        if !event.handled do log.warnf("event wasn't handled properly {}", event)
        switch v in event.variant {
        case Event_Drop_File:
            delete(v.filepath)
            delete(v.data)
        case Event_Keyboard:
        case Event_Mouse:
        case Event_Quit:
        case Event_Window:
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
