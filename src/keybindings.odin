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
            // if e.key.keysym.mod == sdl.KMOD_LCTRL {
            //     editor_move_cursor(.Begin_Line)
            // } else {
                editor_move_cursor(.Backward)
            // }
        }
        case .RIGHT: {
            // if e.key.keysym.mod == sdl.KMOD_LCTRL {
            //     editor_move_cursor(.End_Line)
            // } else {
                editor_move_cursor(.Forward)
            // }
        }
    }
}

handle_key_down :: proc(key: sdl.Keysym) {
    // Generic keybindings
    handle_generic_keybindings(key)

}
