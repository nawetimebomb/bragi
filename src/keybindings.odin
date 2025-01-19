package main

import     "core:fmt"
import     "core:slice"
import     "core:strings"
import sdl "vendor:sdl2"

copy_proc  :: #type proc(str: string)
paste_proc :: #type proc() -> string

Emacs_Keybinds :: struct {
    Cx_pressed: bool,
}

Sublime_Keybinds :: struct {}

Keybinds_Variant :: union {
    Emacs_Keybinds,
    Sublime_Keybinds,
}

Keybinds :: struct {
    last_keystroke : u32,
    variant        : Keybinds_Variant,
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

check_alt_shift :: proc(mod: sdl.Keymod) -> bool {
    return check_alt(mod) && check_shift(mod) && !check_ctrl(mod)
}

check_ctrl_alt :: proc(mod: sdl.Keymod) -> bool {
    return check_alt(mod) && check_ctrl(mod) && !check_shift(mod)
}

check_ctrl_shift :: proc(mod: sdl.Keymod) -> bool {
    return check_ctrl(mod) && check_shift(mod) && !check_alt(mod)
}

check_ctrl_alt_shift :: proc(mod: sdl.Keymod) -> bool {
    return check_alt(mod) && check_ctrl(mod) && check_shift(mod)
}

load_keybinds :: proc() {
    // TODO: Here we should load the configuration from the user
    bragi.keybinds.variant = Emacs_Keybinds{}
}

// These keybindings are shared between all keybinding modes (I.e. Sublime, Emacs, etc)
handle_generic_keybindings :: proc(key: sdl.Keysym) -> bool {
    handled := false
    pane := get_focused_pane()

    A   := check_alt(key.mod)
    AS  := check_alt_shift(key.mod)
    C   := check_ctrl(key.mod)
    CA  := check_ctrl_alt(key.mod)
    CS  := check_ctrl_shift(key.mod)
    CAS := check_ctrl_alt_shift(key.mod)
    S   := check_shift(key.mod)

    #partial switch key.sym {
        case .ESCAPE: {
            when ODIN_DEBUG {
                bragi.ctx.running = false
                handled = true
            }
        }
        case .BACKSPACE: {
            if C {
                delete_backward_word(pane)
            } else {
                delete_backward_char(pane)
            }

            handled = true
        }
        case .DELETE: {
            if C {
                delete_forward_word(pane)
            } else {
                delete_forward_char(pane)
            }

            handled = true
        }
        case .RETURN: {
            newline(pane)
            handled = true
        }
        case .PAGEUP: {
            // buffer_scroll(-buffer_page_size().y)
        }
        case .PAGEDOWN: {
            // buffer_scroll(buffer_page_size().y)
        }
        case .UP: {
            previous_line(pane, S)
            handled = true
        }
        case .DOWN: {
            next_line(pane, S)
            handled = true
        }
        case .LEFT: {
            backward_char(pane, S)
            handled = true
        }
        case .RIGHT: {
            forward_char(pane, S)
            handled = true
        }
    }

    return handled
}

handle_sublime_keybindings :: proc(key: sdl.Keysym) -> bool {
    handled := false
    pane := get_focused_pane()

    A   := check_alt(key.mod)
    AS  := check_alt_shift(key.mod)
    C   := check_ctrl(key.mod)
    CA  := check_ctrl_alt(key.mod)
    CS  := check_ctrl_shift(key.mod)
    CAS := check_ctrl_alt_shift(key.mod)
    S   := check_shift(key.mod)

    #partial switch key.sym {
        case .S: {
            if C {
                save_buffer(pane.buffer)
                handled = true
            }
        }
    }

    return handled
}

handle_global_emacs_keybindings :: proc(key: sdl.Keysym) -> bool {
    handled := false
    pane := get_focused_pane()
    vkb := &bragi.keybinds.variant.(Emacs_Keybinds)

    A   := check_alt(key.mod)
    AS  := check_alt_shift(key.mod)
    C   := check_ctrl(key.mod)
    CA  := check_ctrl_alt(key.mod)
    CS  := check_ctrl_shift(key.mod)
    CAS := check_ctrl_alt_shift(key.mod)
    CX  := vkb.Cx_pressed
    S   := check_shift(key.mod)

    vkb.Cx_pressed = false

    #partial switch key.sym {
        case .A: {
            if C {
                beginning_of_line(pane, S)
                handled = true
            }
        }
        case .B: {
            if A {
                backward_word(pane, S)
                handled = true
            } else if C {
                backward_char(pane, S)
                handled = true
            }
        }
        case .D: {
            if A {
                delete_forward_word(pane)
                handled = true
            } else if C {
                delete_forward_char(pane)
                handled = true
            }
        }
        case .E: {
            if C {
                end_of_line(pane, S)
                handled = true
            }
        }
        case .F: {
            if A {
                forward_word(pane, S)
                handled = true
            } else if C {
                forward_char(pane, S)
                handled = true
            }
        }
        case .G: {
            if C {
                keyboard_quit(pane)
                handled = true
            }
        }
        case .K: {
            if CX {
                kill_current_buffer(pane)
                handled = true
            } else if C {
                kill_line(pane, handle_copy)
                handled = true
            }
        }
        case .N: {
            if C {
                next_line(pane, S)
                handled = true
            }
        }
        case .P: {
            if CX && C {
                mark_buffer(pane)
                handled = true
            } else if C {
                previous_line(pane, S)
                handled = true
            }
        }
        case .S: {
            if CX && C {
                save_buffer(pane.buffer)
                handled = true
            } else if CX {
                save_some_buffers()
                handled = true
            } else if C {
                fmt.println("Search pressed") //buffer_search_forward()
                handled = true
            }
        }
        case .V: {
            switch {
                // case A: buffer_scroll(-buffer_page_size().y)
                // case C: buffer_scroll(buffer_page_size().y)
            }
        }
        case .W: {
            if A {
                kill_region(pane, false, handle_copy)
                handled = true
            } else if C {
                kill_region(pane, true, handle_copy)
                handled = true
            }
        }
        case .X: {
            if A {
                // editor_command_dialog()
            } else if C {
                vkb.Cx_pressed = true
                handled = true
            }
        }
        case .Y: {
            if C {
                yank(pane, handle_paste)
                handled = true
            }
        }
        case .SPACE: {
            if C {
                set_mark(pane)
                handled = true
            }
        }
        case .PERIOD: {
            if AS {
                end_of_buffer(pane)
                handled = true
            }
        }
        case .GREATER: {
            if A {
                end_of_buffer(pane)
                handled = true
            }
        }
        case .COMMA: {
            if AS {
                beginning_of_buffer(pane)
                handled = true
            }
        }
        case .LESS: {
            if A {
                beginning_of_buffer(pane)
                handled = true
            }
        }
        case .SLASH: {
            if CS {
                redo(pane)
                handled = true
            } else if C {
                undo(pane)
                handled = true
            }
        }
        case .QUESTION: {
            if C {
                redo(pane)
                handled = true
            }
        }
    }

    return handled
}

handle_keydown :: proc(key: sdl.Keysym) -> bool {
    handled := false

    // NOTE: Disallow mod keys as keystrokes
    disallowed_keystrokes := [?]sdl.Keycode{
            .LCTRL, .RCTRL, .LSHIFT, .RSHIFT, .LALT, .RALT, .LGUI, .RGUI,
    }

    if slice.contains(disallowed_keystrokes[:], key.sym) {
        return handled
    }

    bragi.keybinds.last_keystroke = sdl.GetTicks()

    // Generic keybindings
    handled = handle_generic_keybindings(key)

    switch v in bragi.keybinds.variant {
    case Emacs_Keybinds:
        handled = handle_global_emacs_keybindings(key)
    case Sublime_Keybinds:
        handled = handle_sublime_keybindings(key)
    }

    return handled
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
