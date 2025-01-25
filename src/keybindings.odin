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

        case .COMMA:            return ","
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
    }

    return ""
}

handle_keydown :: proc(key: sdl.Keysym, pane: ^Pane) -> bool {
    pane.caret.last_keystroke = time.tick_now()

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

    if check_ctrl(key.mod)  { strings.write_string(&keydown, "C-") }
    if check_alt(key.mod)   { strings.write_string(&keydown, "M-") }
    if check_shift(key.mod) { strings.write_string(&keydown, "S-") }

    strings.write_string(&keydown, get_key_representation(key.sym))
    match := strings.to_string(keydown)
    command, exists := bragi.settings.keybindings_table[match]

    if exists {
        do_command(command, pane, match)
    }

    return exists
}

update_input :: proc() {
    e: sdl.Event
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
                    bragi.last_pane    = bragi.current_pane
                    bragi.current_pane = nil
                } else if w.event == .FOCUS_GAINED {
                    bragi.ctx.window_focused = true
                    bragi.current_pane = bragi.last_pane
                }

                if w.event == .RESIZED && w.data1 != 0 && w.data2 != 0 {
                    bragi.ctx.window_size = { e.window.data1, e.window.data2 }
                    recalculate_panes()
                }
                return
            }
            case .DROPFILE: {
                sdl.RaiseWindow(bragi.ctx.window)
                filepath := string(e.drop.file)
                open_file(filepath)
                delete(e.drop.file)
                return
            }
        }

        if bragi.current_pane != nil {
            #partial switch e.type {
                case .MOUSEBUTTONDOWN: {
                    mouse := e.button

                    if mouse.button == 1 {
                        switch mouse.clicks {
                        case 1:
                            bragi.current_pane =
                                find_pane_in_window_coords(mouse.x, mouse.y)
                            mouse_set_point(bragi.current_pane, mouse.x, mouse.y)
                        case 2:
                            bragi.current_pane =
                                find_pane_in_window_coords(mouse.x, mouse.y)
                                mouse_drag_word(bragi.current_pane, mouse.x, mouse.y)
                        case 3:
                            bragi.current_pane =
                                find_pane_in_window_coords(mouse.x, mouse.y)
                                mouse_drag_line(bragi.current_pane, mouse.x, mouse.y)
                        }
                    }

                    return
                }
                case .MOUSEWHEEL: {
                    wheel := e.wheel
                    scroll(bragi.current_pane, wheel.y * -1 * 5)
                    return
                }
                case .KEYDOWN: {
                    input_handled = handle_keydown(e.key.keysym, bragi.current_pane)
                }
                case .TEXTINPUT: {
                    if !input_handled {
                        pane := bragi.current_pane
                        input_char := cstring(raw_data(e.text.text[:]))
                        str := string(input_char)
                        insert(pane.input.buf, pane.input.buf.cursor, str)

                        // if bragi.minibuffer != nil {
                        //     insert(bragi.minibuffer, bragi.minibuffer.cursor, str)
                        // } else {
                        //     switch m in pane.mode {
                        //     case Edit_Mode:

                        //     case Mark_Mode:
                        //         start  := min(m.begin, pane.buffer.cursor)
                        //         end    := max(m.begin, pane.buffer.cursor)
                        //         length := end - start
                        //         pane.buffer.cursor = start
                        //         remove(pane.buffer, pane.buffer.cursor, length)
                        //         set_pane_mode(pane, Edit_Mode{})
                        //         insert(pane.buffer, pane.buffer.cursor, str)
                        //     }
                        // }
                    }
                    return
                }
            }
        }
    }
}

@(private="file")
handle_copy :: proc(str: string) {
    result := strings.clone_to_cstring(str, context.temp_allocator)
    sdl.SetClipboardText(result)
}

@(private="file")
handle_paste :: proc() -> string {
    result := sdl.GetClipboardText()
    return string(result)
}
