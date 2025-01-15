package main

import     "core:fmt"
import sdl "vendor:sdl2"

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
    alt_pressed := is_any_alt_pressed(key.mod)
    ctrl_pressed := is_any_ctrl_pressed(key.mod)
    shift_pressed := is_any_shift_pressed(key.mod)

    #partial switch key.sym {
        case .A: {
            if ctrl_pressed {
                buffer_beginning_of_line()
            }
        }
        case .B: {
            if alt_pressed {
                buffer_backward_word()
            } else if ctrl_pressed {
                buffer_backward_char()
            }
        }
        case .E: {
            if ctrl_pressed {
                buffer_end_of_line()
            }
        }
        case .F: {
            if alt_pressed {
                buffer_forward_word()
            } else if ctrl_pressed {
                buffer_forward_char()
            }
        }
        case .N: {
            if ctrl_pressed {
                buffer_next_line()
            }
        }
        case .P: {
            if ctrl_pressed {
                buffer_previous_line()
            }
        }
        case .V: {
            if alt_pressed && !ctrl_pressed {
                buffer_scroll(-buffer_page_size().y)
            } else if ctrl_pressed && !alt_pressed {
                buffer_scroll(buffer_page_size().y)
            }
        }
        case .PERIOD: {
            if alt_pressed && shift_pressed {
                buffer_end_of_buffer()
            }
        }
        case .GREATER: {
            if alt_pressed {
                buffer_end_of_buffer()
            }
        }
        case .COMMA: {
            if alt_pressed && shift_pressed {
                buffer_beginning_of_buffer()
            }
        }
        case .LESS: {
            if alt_pressed {
                buffer_beginning_of_buffer()
            }
        }
    }
}

handle_key_down :: proc(key: sdl.Keysym) {
    // Generic keybindings
    handle_generic_keybindings(key)

    //handle_sublime_keybindings(key)
    handle_emacs_keybindings(key)
}
