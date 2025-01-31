package main

import     "core:fmt"
import     "core:slice"
import     "core:strings"
import     "core:time"
import sdl "vendor:sdl2"

Copy_Proc  :: #type proc(string)
Paste_Proc :: #type proc() -> string

Keybinds :: struct {
    modifiers: [dynamic]string,
}

KMod :: sdl.KeymodFlag

check_alt :: proc(mod: sdl.Keymod) -> bool {
    return KMod.LALT in mod || KMod.RALT in mod
}

check_ctrl :: proc(mod: sdl.Keymod) -> bool {
    return KMod.LCTRL in mod || KMod.RCTRL in mod
}

check_shift :: proc(mod: sdl.Keymod) -> bool {
    return KMod.LSHIFT in mod || KMod.RSHIFT in mod
}

load_keybinds :: proc() {
    bragi.keybinds.modifiers = make([dynamic]string, 0, 1)
}

get_key_representation :: proc(k: sdl.Keycode) -> string {
    #partial switch k {
        case .BACKSPACE:        return "BACKSPACE"
        case .DELETE:           return "DEL"
        case .ESCAPE:           return "ESC"
        case .RETURN:           return "RET"
        case .SPACE:            return "SPACE"

        case .COMMA:            return ","
        case .GREATER:          return ">"
        case .LESS:             return "<"
        case .PERIOD:           return "."
        case .SLASH:            return "/"

        case .DOWN:             return "Down"
        case .LEFT:             return "Left"
        case .RIGHT:            return "Right"
        case .UP:               return "Up"

	    case .A:                return "a"
	    case .B:                return "b"
	    case .C:                return "c"
	    case .D:                return "d"
	    case .E:                return "e"
	    case .F:                return "f"
	    case .G:                return "g"
	    case .H:                return "h"
	    case .I:                return "i"
	    case .J:                return "j"
	    case .K:                return "k"
	    case .L:                return "l"
	    case .M:                return "m"
	    case .N:                return "n"
	    case .O:                return "o"
	    case .P:                return "p"
	    case .Q:                return "q"
	    case .R:                return "r"
	    case .S:                return "s"
	    case .T:                return "t"
	    case .U:                return "u"
	    case .V:                return "v"
	    case .W:                return "w"
	    case .X:                return "x"
	    case .Y:                return "y"
	    case .Z:                return "z"

	    case .NUM0:             return "0"
	    case .NUM1:             return "1"
	    case .NUM2:             return "2"
	    case .NUM3:             return "3"
	    case .NUM4:             return "4"
	    case .NUM5:             return "5"
	    case .NUM6:             return "6"
	    case .NUM7:             return "7"
	    case .NUM8:             return "8"
	    case .NUM9:             return "9"
    }

    return ""
}

handle_keydown :: proc(p: ^Pane, key: sdl.Keysym) -> bool {
    // NOTE: Disallow mod keys as keystrokes
    disallowed_keystrokes := [?]sdl.Keycode{
            .LCTRL, .RCTRL, .LSHIFT, .RSHIFT, .LALT, .RALT, .LGUI, .RGUI,
    }

    if slice.contains(disallowed_keystrokes[:], key.sym) {
        return false
    }

    keydown := strings.builder_make(context.temp_allocator)

    for len(bragi.keybinds.modifiers) > 0 {
        s := pop(&bragi.keybinds.modifiers)
        strings.write_string(&keydown, s)
        delete(s)
    }

    if check_ctrl(key.mod)  {
        strings.write_string(&keydown, "C-")
    }

    if check_alt(key.mod)   {
        strings.write_string(&keydown, "M-")
    }

    if check_shift(key.mod) {
        strings.write_string(&keydown, "S-")
    }

    strings.write_string(&keydown, get_key_representation(key.sym))
    match := strings.to_string(keydown)
    command, exists := bragi.settings.keybindings_table[match]

    if exists {
        do_command(command, p, match)
    }

    return exists
}

update_input :: proc() {
    e: sdl.Event
    p := &bragi.panes[bragi.focused_index]
    input_handled := false

    for sdl.PollEvent(&e) {
        #partial switch e.type {
            case .QUIT: {
                bragi.ctx.running = false
                return
            }
            case .WINDOWEVENT: {
                w := e.window

                if w.event == .FOCUS_LOST {
                    bragi.ctx.window_focused = false
                } else if w.event == .FOCUS_GAINED {
                    bragi.ctx.window_focused = true
                } else if w.event == .RESIZED && w.data1 != 0 && w.data2 != 0 {
                    bragi.ctx.window_size = { e.window.data1, e.window.data2 }
                    resize_panes()
                }
                return
            }
            case .DROPFILE: {
                sdl.RaiseWindow(bragi.ctx.window)
                filepath := string(e.drop.file)
                editor_open_file(p, filepath)
                delete(e.drop.file)
                return
            }
            case .MOUSEBUTTONDOWN: {
                mouse := e.button

                if mouse.button == 1 {
                    switch mouse.clicks {
                    case 1:
                        editor_switch_to_pane_on_click(mouse.x, mouse.y)
                    case 2:
                        mouse_drag_word(p, mouse.x, mouse.y)
                    case 3:
                        mouse_drag_line(p, mouse.x, mouse.y)
                    }
                }

                return
            }
            case .MOUSEWHEEL: {
                wheel := e.wheel
                scroll(p, wheel.y * -1 * 5)
                return
            }
            case .KEYDOWN: {
                input_handled = handle_keydown(p, e.key.keysym)
            }
            case .TEXTINPUT: {
                if !input_handled {
                    input_char := cstring(raw_data(e.text.text[:]))
                    str := string(input_char)
                    do_command(.self_insert, p, str)
                }
                return
            }
        }
    }
}

handle_copy :: proc(str: string) {
    result := strings.clone_to_cstring(str, context.temp_allocator)
    sdl.SetClipboardText(result)
}

handle_paste :: proc() -> string {
    result := sdl.GetClipboardText()
    return string(result)
}
