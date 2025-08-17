package main

import "core:log"
import "core:slice"

// edit mode is when we're editing a file
edit_mode_keyboard_event_handler :: proc(event: Event_Keyboard) -> bool {
    pane := active_pane
    buffer := pane.buffer

    if event.is_text_input {
        length_of_inserted_text := insert_at_points(pane, buffer, event.text)
        return length_of_inserted_text > 0
    } else {
        // handle the generic ones first
        #partial switch event.key_code {
            case .K_ENTER: {
                insert_newlines_and_indent(pane, buffer)
                return true
            }
            case .K_BACKSPACE: {
                remove_to(pane, buffer, .left)
                return true
            }
            case .K_DELETE: {
                remove_to(pane, buffer, .right)
                return true
            }
        }

        cmd := map_keystroke_to_command(event.key_code, event.modifiers)

        switch cmd {
        case .noop:     // not handled, it should report for now
        case .modifier: return true // not handled (for now)

        case .increase_font_size:
            current_index, _ := slice.binary_search(font_sizes, pane.local_font_size)
            if current_index + 1 < len(font_sizes) {
                pane.local_font_size = font_sizes[current_index + 1]
                update_all_pane_textures()
            }
            return true
        case .decrease_font_size:
            current_index, _ := slice.binary_search(font_sizes, pane.local_font_size)
            if current_index > 0 {
                pane.local_font_size = font_sizes[current_index - 1]
                update_all_pane_textures()
            }
            return true
        case .reset_font_size:
            default_font_size := i32(settings.editor_font_size)
            if pane.local_font_size != default_font_size {
                pane.local_font_size = default_font_size
                update_all_pane_textures()
            }
            return true

        case .quit_mode:

        case .select_all:
            clear(&pane.cursors)
            add_cursor(pane, len(pane.contents.buf))
            pane.cursors[0].pos = 0
            return true

        case .move_start:
            move_to(pane, .start)
            return true
        case .move_end:
            move_to(pane, .end)
            return true
        case .move_down:
            move_to(pane, .down)
            return true
        case .move_left:
            move_to(pane, .left)
            return true
        case .move_left_word:
            move_to(pane, .left_word)
            return true
        case .move_right:
            move_to(pane, .right)
            return true
        case .move_right_word:
            move_to(pane, .right_word)
            return true
        case .move_up:
            move_to(pane, .up)
            return true

        case .select_left:
            select_to(pane, .left)
            return true
        case .select_right:
            select_to(pane, .right)
            return true

        case .find_file: widget_open(.find_file)

        case .save_buffer:
        case .save_buffer_as:
        case .switch_buffer:
        case .kill_current_buffer:

        case .search_backward:
        case .search_forward:

        case .delete_this_pane:
        case .delete_other_pane:
        case .new_pane_to_the_right:
            result := pane_create()
            switch_to_buffer(result, buffer)
            active_pane = result
            return true
        case .other_pane:

        case .undo:
            undo_done, cursors, pieces := undo(buffer, &buffer.undo, &buffer.redo)
            if undo_done {
                delete(pane.cursors)
                delete(buffer.pieces)
                pane.cursors = slice.clone_to_dynamic(cursors)
                buffer.pieces = slice.clone_to_dynamic(pieces)
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

move_to :: proc(pane: ^Pane, t: Translation) {
    if .Selection in pane.cursor_modes {
        select_to(pane, t)
        return
    }

    for &cursor in pane.cursors {
        if t == .left && has_selection(cursor) {
            low, _ := sorted_cursor(cursor)
            cursor.pos = low
            cursor.sel = low
        } else if t == .right && has_selection(cursor) {
            _, high := sorted_cursor(cursor)
            cursor.pos = high
            cursor.sel = high
        } else {
            coords := cursor_offset_to_coords(pane, get_lines_array(pane), cursor.pos)
            last_column := -1 if t != .up && t != .down else max(cursor.last_column, coords.column)
            result, result_column := translate_position(pane, cursor.pos, t, last_column)
            cursor.pos = result
            cursor.sel = result
            cursor.last_column = result_column
        }
    }
}

select_to :: proc(pane: ^Pane, t: Translation) {
    for &cursor in pane.cursors {
        cursor.pos, _ = translate_position(pane, cursor.pos, t)
    }
}

insert_at_points :: proc(pane: ^Pane, buffer: ^Buffer, text: string) -> (total_length_of_inserted_characters: int) {
    profiling_start("inserting text input")
    buffer.cursors = pane.cursors[:]

    for &cursor in pane.cursors {
        offset := insert_at(buffer, cursor.pos, text)
        total_length_of_inserted_characters += offset
        cursor.pos += offset
        cursor.sel = cursor.pos
    }
    profiling_end()
    return
}

insert_newlines_and_indent :: proc(pane: ^Pane, buffer: ^Buffer) -> (total_length_of_inserted_characters: int) {
    profiling_start("inserting newline and indenting")
    buffer.cursors = pane.cursors[:]

    for &cursor in pane.cursors {
        // TODO(nawe) add indent
        offset := insert_at(buffer, cursor.pos, "\n")
        cursor.pos += offset
        cursor.sel = cursor.pos
        total_length_of_inserted_characters += offset
    }
    profiling_end()
    return
}

remove_to :: proc(pane: ^Pane, buffer: ^Buffer, t: Translation) -> (total_amount_of_removed_characters: int) {
    profiling_start("removing text")
    buffer.cursors = pane.cursors[:]

    for &cursor in pane.cursors {
        if !has_selection(cursor) {
            cursor.pos, _ = translate_position(pane, cursor.pos, t)
        }

        low, high := sorted_cursor(cursor)
        if low != high {
            remove_at(buffer, low, high - low)
            cursor.pos = low
            cursor.sel = low
        }
    }

    profiling_end()
    return
}
