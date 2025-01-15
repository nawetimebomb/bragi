package main

import     "core:fmt"
import sdl "vendor:sdl2"

KMod :: sdl.KeymodFlag

is_any_ctrl_pressed :: proc(mod: sdl.Keymod) -> bool {
    return KMod.LCTRL in mod || KMod.RCTRL in mod
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

handle_key_down :: proc(key: sdl.Keysym) {
    // Generic keybindings
    handle_generic_keybindings(key)

}
