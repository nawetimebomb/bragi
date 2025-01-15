package main

import     "core:fmt"
import     "core:slice"
import sdl "vendor:sdl2"

Emacs_Keybinds :: struct {
    Cx_pressed: bool,
}

Keybinds_Variant :: union {
    Emacs_Keybinds,
}

Keybinds :: struct {
    last_keystroke: u32,
    variant: Keybinds_Variant,
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
handle_generic_keybindings :: proc(key: sdl.Keysym) {
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
            }
        }
        case .BACKSPACE: {
            switch {
            case C: buffer_delete_word_backward()
            case  : buffer_delete_char_backward()
            }
        }
        case .DELETE: {
            switch {
            case C: buffer_delete_word_forward()
            case  : buffer_delete_char_forward()
            }
        }
        case .RETURN: {
            buffer_newline()
        }
        case .PAGEUP: {
            buffer_scroll(-buffer_page_size().y)
        }
        case .PAGEDOWN: {
            buffer_scroll(buffer_page_size().y)
        }
        case .UP: {
            switch {
            case C: buffer_backward_paragraph()
            case  : buffer_previous_line()
            }
        }
        case .DOWN: {
            switch {
            case C: buffer_forward_paragraph()
            case  : buffer_next_line()
            }
        }
        case .LEFT: {
            switch {
            case C: buffer_backward_word()
            case  : buffer_backward_char()
            }
        }
        case .RIGHT: {
            switch {
            case C: buffer_forward_word()
            case  : buffer_forward_char()
            }
        }
    }
}

handle_sublime_keybindings :: proc(key: sdl.Keysym) {
    A   := check_alt(key.mod)
    AS  := check_alt_shift(key.mod)
    C   := check_ctrl(key.mod)
    CA  := check_ctrl_alt(key.mod)
    CS  := check_ctrl_shift(key.mod)
    CAS := check_ctrl_alt_shift(key.mod)
    S   := check_shift(key.mod)

    #partial switch key.sym {
        case .S: {
            switch {
            case C: editor_save_file()
            }
        }
    }
}

handle_emacs_keybindings :: proc(key: sdl.Keysym) {
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
            switch {
            case C: buffer_beginning_of_line()
            }
        }
        case .B: {
            switch {
            case A: buffer_backward_word()
            case C: buffer_backward_char()
            }
        }
        case .D: {
            switch {
            case A: buffer_delete_word_forward()
            case C: buffer_delete_char_forward()
            }
        }
        case .E: {
            switch {
            case C: buffer_end_of_line()
            }
        }
        case .F: {
            switch {
            case A: buffer_forward_word()
            case C: buffer_forward_char()
            }
        }
        case .N: {
            switch {
            case C: buffer_next_line()
            }
        }
        case .P: {
            switch {
            case C: buffer_previous_line()
            }
        }
        case .S: {
            switch {
            case CX && C: editor_save_file()
            case C: fmt.println("Search pressed") //buffer_search_forward()
            }
        }
        case .V: {
            switch {
            case A: buffer_scroll(-buffer_page_size().y)
            case C: buffer_scroll(buffer_page_size().y)
            }
        }
        case .X: {
            switch {
            case A: // editor_command_dialog()
            case C: vkb.Cx_pressed = true
            }
        }
        case .PERIOD: {
            switch {
            case AS: buffer_end_of_buffer()
            }
        }
        case .GREATER: {
            switch {
            case A: buffer_end_of_buffer()
            }
        }
        case .COMMA: {
            switch {
            case A && S: buffer_beginning_of_buffer()
            }
        }
        case .LESS: {
            switch {
            case A: buffer_beginning_of_buffer()
            }
        }
    }
}

handle_key_down :: proc(key: sdl.Keysym) {
    // NOTE: Disallow mod keys as keystrokes
    disallowed_keystrokes := [?]sdl.Keycode{
            .LCTRL, .RCTRL, .LSHIFT, .RSHIFT, .LALT, .RALT, .LGUI, .RGUI,
    }

    if slice.contains(disallowed_keystrokes[:], key.sym) {
        return
    }

    bragi.keybinds.last_keystroke = sdl.GetTicks()

    // Generic keybindings
    handle_generic_keybindings(key)

    //handle_sublime_keybindings(key)
    handle_emacs_keybindings(key)
}
