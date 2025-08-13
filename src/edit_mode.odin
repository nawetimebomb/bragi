package main

import "core:time"

// edit mode is when we're editing a file
edit_mode_keyboard_event_handler :: proc(event: Event_Keyboard) -> bool {
    pane := active_pane
    buffer := pane.buffer

    if event.is_text_input {
        length_of_inserted_text := insert_at_points(buffer, event.text)
        pane.last_keystroke = time.tick_now()
        return length_of_inserted_text > 0
    } else {
        // handle the generic ones first
        #partial switch event.key_pressed {
            case .Enter: {
                insert_newlines_and_indent(buffer)
                pane.last_keystroke = time.tick_now()
                return true
            }
            case .Backspace: {
                remove_at_points(buffer, -1)
                pane.last_keystroke = time.tick_now()
                return true
            }
        }

        cmd := map_keystroke_to_command(event.key_pressed, event.modifiers)
        _ = cmd
        _ = buffer
    }

    return false
}
