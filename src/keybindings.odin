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

is_any_alt_pressed :: proc(mod: sdl.Keymod) -> bool {
    return KMod.LALT in mod || KMod.RALT in mod
}

is_any_ctrl_pressed :: proc(mod: sdl.Keymod) -> bool {
    return KMod.LCTRL in mod || KMod.RCTRL in mod
}

is_any_shift_pressed :: proc(mod: sdl.Keymod) -> bool {
    return KMod.LSHIFT in mod || KMod.RSHIFT in mod
}

is_only_alt_pressed :: proc(mod: sdl.Keymod) -> bool {
    return is_any_alt_pressed(mod) &&
        !is_any_ctrl_pressed(mod) && !is_any_shift_pressed(mod)
}

is_only_ctrl_pressed :: proc(mod: sdl.Keymod) -> bool {
    return is_any_ctrl_pressed(mod) &&
        !is_any_alt_pressed(mod) && !is_any_shift_pressed(mod)
}

load_keybinds :: proc() {
    // TODO: Here we should load the configuration from the user
    bragi.keybinds.variant = Emacs_Keybinds{}
}

// These keybindings are shared between all keybinding modes (I.e. Sublime, Emacs, etc)
handle_generic_keybindings :: proc(key: sdl.Keysym) {
    #partial switch key.sym {
        case .ESCAPE: {
            when ODIN_DEBUG {
                bragi.ctx.running = false
            }
        }
        case .BACKSPACE: {
            if is_any_ctrl_pressed(key.mod) {
                buffer_delete_word_backward()
            } else {
                buffer_delete_char_backward()
            }
        }
        case .DELETE: {
            if is_any_ctrl_pressed(key.mod) {
                buffer_delete_word_forward()
            } else {
                buffer_delete_char_forward()
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
            if is_any_ctrl_pressed(key.mod) {
                buffer_backward_paragraph()
            } else {
                buffer_previous_line()
            }
        }
        case .DOWN: {
            if is_any_ctrl_pressed(key.mod) {
                buffer_forward_paragraph()
            } else {
                buffer_next_line()
            }
        }
        case .LEFT: {
            if is_any_ctrl_pressed(key.mod) {
                buffer_backward_word()
            } else {
                buffer_backward_char()
            }
        }
        case .RIGHT: {
            if is_any_ctrl_pressed(key.mod) {
                buffer_forward_word()
            } else {
                buffer_forward_char()
            }
        }
    }
}

handle_sublime_keybindings :: proc(key: sdl.Keysym) {
    #partial switch key.sym {
        case .S: {
            if is_any_ctrl_pressed(key.mod) {
                editor_save_file()
            }
        }
    }
}

handle_emacs_keybindings :: proc(key: sdl.Keysym) {
    vkb := &bragi.keybinds.variant.(Emacs_Keybinds)

    A  := is_only_alt_pressed(key.mod)
    C  := is_only_ctrl_pressed(key.mod)
    CX := vkb.Cx_pressed
    S  := is_any_shift_pressed(key.mod)

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
            case A && S: buffer_end_of_buffer()
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
