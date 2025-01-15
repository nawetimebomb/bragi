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
                editor_delete_word_at_point(.Left)
            } else {
                editor_delete_char_at_point(.Left)
            }
        }
        case .DELETE: {
            if is_any_ctrl_pressed(key.mod) {
                editor_delete_word_at_point(.Right)
            } else {
                editor_delete_char_at_point(.Right)
            }
        }
        case .RETURN: {
            editor_insert_new_line_and_indent()
        }
    }
}

handle_key_down :: proc(key: sdl.Keysym) {
    // Generic keybindings
    handle_generic_keybindings(key)

}
