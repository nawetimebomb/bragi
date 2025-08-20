package main

import "core:log"
import "core:slice"

// edit mode is when we're editing a file
edit_mode_keyboard_event_handler :: proc(event: Event_Keyboard, cmd: Command) -> bool {
    pane := active_pane
    buffer := pane.buffer

    if event.is_text_input {
        length_of_inserted_text := insert_at_points(pane, buffer, event.text)
        return length_of_inserted_text > 0
    }

    // handle the generic ones first
    #partial switch event.key_code {
        case .K_ENTER: {
            insert_newlines_and_indent(pane, buffer)
            return true
        }
        case .K_BACKSPACE: {
            t: Translation = .left

            if .Ctrl in event.modifiers || .Alt in event.modifiers {
                t = .prev_word
            }

            remove_to(pane, buffer, t)
            return true
        }
        case .K_DELETE: {
            t: Translation = .right

            if .Ctrl in event.modifiers || .Alt in event.modifiers {
                t = .next_word
            }

            remove_to(pane, buffer, t)
            return true
        }
    }

    switch cmd {
    case .noop:      return false // not handled, it should report for now
    case .modifier:  // handled globally
    case .quit_mode: // handled globally

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

    case .toggle_selection_mode:

    case .clone_cursor_down: clone_to(pane, .down)

    case .move_start:
        move_to(pane, .start)
        return true
    case .move_end:
        move_to(pane, .end)
        return true
    case .move_left:
        move_to(pane, .left)
        return true
    case .move_right:
        move_to(pane, .right)
        return true
    case .move_down:
        move_to(pane, .down)
        return true
    case .move_up:
        move_to(pane, .up)
        return true
    case .move_prev_word:
        move_to(pane, .prev_word)
        return true
    case .move_next_word:
        move_to(pane, .next_word)
        return true
    case .move_prev_paragraph:
        move_to(pane, .prev_paragraph)
        return true
    case .move_next_paragraph:
        move_to(pane, .next_paragraph)
        return true
    case .move_beginning_of_line:
        move_to(pane, .beginning_of_line)
        return true
    case .move_end_of_line:
        move_to(pane, .end_of_line)
        return true

    case .select_all:
        clear(&pane.cursors)
        add_cursor(pane, len(pane.contents.buf))
        pane.cursors[0].pos = 0
        return true
    case .select_start:
        select_to(pane, .start)
        return true
    case .select_end:
        select_to(pane, .end)
        return true
    case .select_left:
        select_to(pane, .left)
        return true
    case .select_right:
        select_to(pane, .right)
        return true
    case .select_down:
        select_to(pane, .down)
        return true
    case .select_up:
        select_to(pane, .up)
        return true
    case .select_prev_word:
        select_to(pane, .prev_word)
        return true
    case .select_next_word:
        select_to(pane, .next_word)
        return true
    case .select_prev_paragraph:
        select_to(pane, .prev_paragraph)
        return true
    case .select_next_paragraph:
        select_to(pane, .next_paragraph)
        return true
    case .select_beginning_of_line:
        select_to(pane, .beginning_of_line)
        return true
    case .select_end_of_line:
        select_to(pane, .end_of_line)
        return true

    case .find_buffer:
        widget_open_find_buffer()
        return true
    case .find_file:
        widget_open_find_file()
        return true

    case .close_current_buffer:
        index := buffer_index(buffer)
        ordered_remove(&open_buffers, index)
        buffer_destroy(buffer)
        active_pane.buffer = nil
        if len(open_buffers) == 0 {
            switch_to_buffer(active_pane, buffer_get_or_create_empty())
        } else {
            index = clamp(index, 0, len(open_buffers) - 1)
            switch_to_buffer(active_pane, open_buffers[index])
        }
        return true
    case .save_buffer:
    case .save_buffer_as:

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

    return false
}

clone_to :: proc(pane: ^Pane, t: Translation) {
    // TODO(nawe) should use the last active cursor instead
    last_cursor := pane.cursors[len(pane.cursors) - 1]
    cloned_cursor := clone_cursor(pane, last_cursor)
    move_to(pane, t, cloned_cursor)
}

move_to :: proc(pane: ^Pane, t: Translation, cursor_to_move: ^Cursor = nil) {
    move_cursor :: #force_inline proc(pane: ^Pane, cursor: ^Cursor, t: Translation) {
        if t == .left && has_selection(cursor^) {
            low, _ := sorted_cursor(cursor^)
            cursor.pos = low
            cursor.sel = low
        } else if t == .right && has_selection(cursor^) {
            _, high := sorted_cursor(cursor^)
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

    if .Selection in pane.cursor_modes {
        select_to(pane, t, cursor_to_move)
        return
    }

    if cursor_to_move != nil {
        move_cursor(pane, cursor_to_move, t)
    } else {
        for &cursor in pane.cursors {
            move_cursor(pane, &cursor, t)
        }
    }

    _maybe_merge_overlapping_cursors(pane)
}

select_to :: proc(pane: ^Pane, t: Translation, cursor_to_select: ^Cursor = nil) {
    if cursor_to_select != nil {
        cursor_to_select.pos, _ = translate_position(pane, cursor_to_select.pos, t)
    } else {
        for &cursor in pane.cursors {
            cursor.pos, _ = translate_position(pane, cursor.pos, t)
        }
    }

    _maybe_merge_overlapping_cursors(pane)
}

remove_to :: proc(pane: ^Pane, buffer: ^Buffer, t: Translation) -> (total_amount_of_removed_characters: int) {
    profiling_start("removing text")
    copy_cursors(pane, buffer)

    for &cursor, current_index in pane.cursors {
        if !has_selection(cursor) {
            cursor.pos, _ = translate_position(pane, cursor.pos, t)
        }

        low, high := sorted_cursor(cursor)
        offset := high - low
        if low != high {
            remove_at(buffer, low, offset)
            cursor.pos = low
            cursor.sel = low
        }

        for next_index in current_index + 1..<len(pane.cursors) {
            pane.cursors[next_index].pos -= offset
            pane.cursors[next_index].sel -= offset
        }
    }

    _maybe_merge_overlapping_cursors(pane)

    profiling_end()
    return
}

insert_at_points :: proc(pane: ^Pane, buffer: ^Buffer, text: string) -> (total_length_of_inserted_characters: int) {
    profiling_start("inserting text input")
    copy_cursors(pane, buffer)

    for &cursor, current_index in pane.cursors {
        offset := insert_at(buffer, cursor.pos, text)
        total_length_of_inserted_characters += offset
        cursor.pos += offset
        cursor.sel = cursor.pos

        for next_index in current_index + 1..<len(pane.cursors) {
            pane.cursors[next_index].pos += offset
            pane.cursors[next_index].sel += offset
        }
    }
    profiling_end()
    return
}

insert_newlines_and_indent :: proc(pane: ^Pane, buffer: ^Buffer) -> (total_length_of_inserted_characters: int) {
    profiling_start("inserting newline and indenting")
    copy_cursors(pane, buffer)

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

@(private="file")
_maybe_merge_overlapping_cursors :: proc(pane: ^Pane) {
    if len(pane.cursors) < 2 do return

    for i in 0..<len(pane.cursors) {
        for j in 1..<len(pane.cursors) {
            if i == j do continue
            icursor := pane.cursors[i]
            jcursor := pane.cursors[j]

            if !has_selection(icursor) && !has_selection(jcursor) {
                ipos := icursor.pos
                jpos := jcursor.pos

                if ipos == jpos {
                    log.debugf("merging cursors {} and {}", i + 1, j + 1)
                    ordered_remove(&pane.cursors, i)
                    flag_pane(pane, {.Need_Full_Repaint})
                }
            } else {
                _, ihi := sorted_cursor(icursor)
                jlo, jhi := sorted_cursor(jcursor)

                if ihi >= jlo && ihi < jhi {
                    if icursor.pos > icursor.sel {
                        // going to the right
                        pane.cursors[i].pos = max(icursor.pos, jcursor.pos)
                        pane.cursors[i].sel = min(icursor.sel, jcursor.sel)
                    } else {
                        // going to the left
                        pane.cursors[i].pos = min(icursor.pos, jcursor.pos)
                        pane.cursors[i].sel = max(icursor.sel, jcursor.sel)
                    }

                    log.debugf("merging cursors {} and {}", i + 1, j + 1)
                    pane.cursors[i].last_column = -1
                    pane.cursors[i].active = true
                    ordered_remove(&pane.cursors, j)
                    flag_pane(pane, {.Need_Full_Repaint})
                }
            }
        }
    }
}
