package main

import     "core:fmt"
import     "core:slice"
import     "core:strings"
import     "core:time"
import sdl "vendor:sdl2"

Copy_Proc  :: #type proc(string)
Paste_Proc :: #type proc() -> string

Emacs_Keybinds :: struct {
    Cx_pressed: bool,
}

Sublime_Keybinds :: struct {}

Keybinds_Variant :: union {
    Emacs_Keybinds,
    Sublime_Keybinds,
}

Keybinds :: struct {
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
handle_generic_keybindings :: proc(key: sdl.Keysym, pane: ^Pane) -> bool {
    handled := false

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

handle_sublime_keybindings :: proc(key: sdl.Keysym, pane: ^Pane) -> bool {
    handled := false

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

handle_global_emacs_keybindings :: proc(key: sdl.Keysym, pane: ^Pane) -> bool {
    handled := false
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
        case .R: {
            if C {
                search_backward(pane)
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
                search_forward(pane)
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

handle_keydown :: proc(key: sdl.Keysym, pane: ^Pane) -> bool {
    handled := false

    // NOTE: Disallow mod keys as keystrokes
    disallowed_keystrokes := [?]sdl.Keycode{
            .LCTRL, .RCTRL, .LSHIFT, .RSHIFT, .LALT, .RALT, .LGUI, .RGUI,
    }

    if slice.contains(disallowed_keystrokes[:], key.sym) {
        return handled
    }

    pane.caret.last_keystroke_time = time.tick_now()

    // Generic keybindings
    handled = handle_generic_keybindings(key, pane)

    switch v in bragi.keybinds.variant {
    case Emacs_Keybinds:
        handled = handle_global_emacs_keybindings(key, pane)
    case Sublime_Keybinds:
        handled = handle_sublime_keybindings(key, pane)
    }

    return handled
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
                    bragi.ctx.window_size = {
                        e.window.data1, e.window.data2,
                    }
                    refresh_panes()
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
                            if clicks_on_pane_contents(mouse.x, mouse.y) {
                                mouse_set_point(bragi.current_pane, mouse.x, mouse.y)
                            }
                        case 2:
                            if clicks_on_pane_contents(mouse.x, mouse.y) {
                                mouse_drag_word(bragi.current_pane, mouse.x, mouse.y)
                            }
                        case 3:
                            if clicks_on_pane_contents(mouse.x, mouse.y) {
                                mouse_drag_line(bragi.current_pane, mouse.x, mouse.y)
                            }
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
                        search_mode, search_enabled := pane.mode.(Search_Mode)
                        mark_mode, mark_enabled := pane.mode.(Mark_Mode)
                        input_char := cstring(raw_data(e.text.text[:]))
                        str := string(input_char)

                        switch {
                        case mark_enabled:
                            start  := min(mark_mode.begin, pane.buffer.cursor)
                            end    := max(mark_mode.begin, pane.buffer.cursor)
                            length := end - start
                            pane.buffer.cursor = start

                            delete_at(pane.buffer, pane.buffer.cursor, length)
                            set_pane_mode(pane, Edit_Mode{})
                            insert_at(pane.buffer, pane.buffer.cursor, str)
                        case search_enabled:
                            insert_at(search_mode.buffer, search_mode.buffer.cursor, str)

                            if search_mode.direction == .Forward {
                                search_forward(pane)
                            } else {
                                search_backward(pane)
                            }
                        case :
                            insert_at(pane.buffer, pane.buffer.cursor, str)
                        }
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
