package main

import "core:log"
import "core:slice"
import "core:strings"
import "core:time"

// edit mode is when we're editing a file
edit_mode_keyboard_event_handler :: proc(event: Event_Keyboard) -> bool {
    pane := active_pane
    buffer := pane.buffer

    if event.is_text_input {
        length_of_inserted_text := insert_at_points(pane, buffer, event.text)
        pane.last_keystroke = time.tick_now()
        return length_of_inserted_text > 0
    } else {
        // handle the generic ones first
        #partial switch event.key_pressed {
            case .Enter: {
                insert_newlines_and_indent(pane, buffer)
                pane.last_keystroke = time.tick_now()
                return true
            }
            case .Backspace: {
                remove_at_points(pane, buffer, -1)
                pane.last_keystroke = time.tick_now()
                return true
            }
            case .Delete: {
                remove_at_points(pane, buffer, 1)
                pane.last_keystroke = time.tick_now()
                return true
            }
        }

        cmd := map_keystroke_to_command(event.key_pressed, event.modifiers)

        switch cmd {
        case .noop:     // not handled, it should report for now
        case .modifier: // not handled (for now)

        case .increase_font_size:
        case .decrease_font_size:
        case .reset_font_size:

        case .quit_mode:

        case .find_file:
        case .save_file:
        case .save_file_as:
        case .switch_buffer:
        case .kill_current_buffer:

        case .search_backward:
        case .search_forward:

        case .delete_this_pane:
        case .delete_other_pane:
        case .new_pane_to_the_right:
        case .other_pane:

        case .undo:
            undo_done, cursors, pieces := undo(buffer, &buffer.undo, &buffer.redo)
            if undo_done {
                delete(pane.cursors)
                delete(buffer.pieces)
                pane.cursors = slice.clone_to_dynamic(cursors)
                buffer.pieces = slice.clone_to_dynamic(pieces)
                pane.last_keystroke = time.tick_now()
                return true
            }
            log.debug("no more history to undo")
            return true
        case .redo:
            redo_done, cursors, pieces := undo(buffer, &buffer.redo, &buffer.undo)
            if redo_done {
                delete(pane.cursors)
                delete(buffer.pieces)
                pane.cursors = slice.clone_to_dynamic(cursors)
                buffer.pieces = slice.clone_to_dynamic(pieces)
                pane.last_keystroke = time.tick_now()
                return true
            }
            log.debug("no more history to redo")
            return true
        case .cut_region:
        case .cut_line:
        case .copy_region:
        case .copy_line:
        case .paste:
        case .paste_from_history:
        }
    }

    return false
}

move_all_cursors_from_index :: #force_inline proc(pane: ^Pane, starting_cursor, offset: int) {
    for cursor_index in starting_cursor..<len(pane.cursors) {
        cursor := &pane.cursors[cursor_index]
        cursor.pos = clamp(cursor.pos + offset, 0, len(pane.contents.buf) + offset)
        cursor.sel = cursor.pos
        cursor.last_column = -1
    }
}

insert_at_points :: proc(pane: ^Pane, buffer: ^Buffer, text: string) -> (total_length_of_inserted_characters: int) {
    profiling_start("inserting text input")
    buffer.cursors = pane.cursors[:]

    for cursor, cursor_index in pane.cursors {
        offset := insert_at(buffer, cursor.pos, text)
        total_length_of_inserted_characters += offset
        move_all_cursors_from_index(pane, cursor_index, offset)
    }
    profiling_end()
    return
}

insert_newlines_and_indent :: proc(pane: ^Pane, buffer: ^Buffer) -> (total_length_of_inserted_characters: int) {
    profiling_start("inserting newline and indenting")
    buffer.cursors = pane.cursors[:]

    for cursor, cursor_index in pane.cursors {
        // TODO(nawe) add indent
        offset := insert_at(buffer, cursor.pos, "\n")
        total_length_of_inserted_characters += offset
        move_all_cursors_from_index(pane, cursor_index, offset)
    }
    profiling_end()
    return
}

remove_at_points :: proc(pane: ^Pane, buffer: ^Buffer, amount: int) -> (total_amount_of_removed_characters: int) {
    profiling_start("removing text")
    buffer.cursors = pane.cursors[:]

    for cursor, cursor_index in pane.cursors {
        characters_to_remove := amount
        current_buffer_value := strings.to_string(pane.contents)

        if cursor.pos == 0 && amount < 0 || cursor.pos == len(current_buffer_value) && amount > 0 {
            continue
        } else if amount < 0 {
            // make sure we stop at 0
            safe_characters_to_remove := max(amount, -cursor.pos)

            // NOTE(nawe) because we support unicode, we want to check
            // the length of the rune and add to the total amount of
            // characters to remove.
            substring := current_buffer_value[cursor.pos + safe_characters_to_remove:cursor.pos]
            characters_to_remove = 0
            for index := 0; index < len(substring); index += 1 {
                characters_to_remove += 1
                if is_continuation_byte(substring[index]) do characters_to_remove += 1
            }

            remove_at(buffer, cursor.pos, -characters_to_remove)
            move_all_cursors_from_index(pane, cursor_index, -characters_to_remove)
        } else {
            safe_characters_to_remove := min(amount, len(current_buffer_value))

            substring := current_buffer_value[cursor.pos:safe_characters_to_remove + cursor.pos]
            characters_to_remove = 0
            for index := 0; index < len(substring); index += 1 {
                characters_to_remove += 1
                if is_continuation_byte(substring[index]) do characters_to_remove += 1
            }

            remove_at(buffer, cursor.pos, characters_to_remove)
            move_all_cursors_from_index(pane, cursor_index + 1, -characters_to_remove)
        }

        total_amount_of_removed_characters += abs(characters_to_remove)
    }
    profiling_end()
    return
}
