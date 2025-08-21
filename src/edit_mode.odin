package main

import "core:encoding/uuid"
import "core:log"
import "core:slice"

// edit mode is when we're editing a file
edit_mode_keyboard_event_handler :: proc(event: Event_Keyboard, cmd: Command) -> bool {
    pane := active_pane
    buffer := pane.buffer

    if event.is_text_input {
        length_of_inserted_text := insert_at_points(pane, event.text)
        return length_of_inserted_text > 0
    }

    // handle the generic ones first
    #partial switch event.key_code {
        case .K_ENTER: {
            insert_newlines_and_indent(pane)
            return true
        }
        case .K_BACKSPACE: {
            t: Translation = .left

            if .Ctrl in event.modifiers || .Alt in event.modifiers {
                t = .prev_word
            }

            remove_to(pane, t)
            return true
        }
        case .K_DELETE: {
            t: Translation = .right

            if .Ctrl in event.modifiers || .Alt in event.modifiers {
                t = .next_word
            }

            remove_to(pane, t)
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
        if pane.cursor_selecting {
            pane.cursor_selecting = false
            for &cursor in pane.cursors do cursor.sel = cursor.pos
            return true
        } else {
            pane.cursor_selecting = true
            for &cursor in pane.cursors do cursor.active = true
            return true
        }

    case .prev_cursor:
        if pane.cursor_selecting {
            pane.cursor_selecting = false
            for &cursor in pane.cursors do cursor.sel = cursor.pos
        }

        current_cursor_index := -1

        for &cursor, index in pane.cursors {
            if cursor.active {
                current_cursor_index = index
                cursor.active = false
            }
        }

        current_cursor_index -= 1
        if current_cursor_index < 0 do current_cursor_index = len(pane.cursors) - 1
        pane.cursors[current_cursor_index].active = true
        return true
    case .next_cursor:
        if pane.cursor_selecting {
            pane.cursor_selecting = false
            for &cursor in pane.cursors do cursor.sel = cursor.pos
        }

        current_cursor_index := -1

        for &cursor, index in pane.cursors {
            if cursor.active {
                current_cursor_index = index
                cursor.active = false
            }
        }

        current_cursor_index += 1
        if current_cursor_index > len(pane.cursors) - 1 do current_cursor_index = 0
        pane.cursors[current_cursor_index].active = true
        return true
    case .all_cursors:
        for &cursor in pane.cursors do cursor.active = true
        return true

    case .clone_cursor_start:
        clone_to(pane, .start)
        return true
    case .clone_cursor_end:
        clone_to(pane, .end)
        return true
    case .clone_cursor_left:
        clone_to(pane, .left)
        return true
    case .clone_cursor_right:
        clone_to(pane, .right)
        return true
    case .clone_cursor_down:
        clone_to(pane, .down)
        return true
    case .clone_cursor_up:
        clone_to(pane, .up)
        return true
    case .clone_cursor_prev_word:
        clone_to(pane, .prev_word)
        return true
    case .clone_cursor_next_word:
        clone_to(pane, .next_word)
        return true
    case .clone_cursor_prev_paragraph:
        clone_to(pane, .prev_paragraph)
        return true
    case .clone_cursor_next_paragraph:
        clone_to(pane, .next_paragraph)
        return true
    case .clone_cursor_beginning_of_line:
        clone_to(pane, .beginning_of_line)
        return true
    case .clone_cursor_end_of_line:
        clone_to(pane, .end_of_line)
        return true

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
        add_cursor(pane, len(pane.contents))
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

    case .remove_left:
        remove_to(pane, .left)
    case .remove_right:
        remove_to(pane, .right)

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
        if buffer.filepath == "" {
            // TODO(nawe) should open the file selector to allow and select the file
            unimplemented()
        } else {
            buffer_save(buffer)
        }

        return true

    case .save_buffer_as:
        unimplemented()

    case .search_backward:
    case .search_forward:

    case .close_this_pane:
        if len(open_panes) == 1 do return true
        pane_index_to_close := -1
        for other, index in open_panes {
            if active_pane.uuid == other.uuid {
                pane_index_to_close = index
                break
            }
        }
        new_pane_index := pane_index_to_close < len(open_panes) - 1 ? pane_index_to_close + 1 : 0
        old_pane := active_pane
        active_pane = open_panes[new_pane_index]
        ordered_remove(&open_panes, pane_index_to_close)
        pane_destroy(old_pane)
        update_all_pane_textures()
        return true
    case .close_other_panes:
        if len(open_panes) == 1 do return true
        ids_to_remove := make([dynamic]uuid.Identifier, 0, len(open_panes), context.temp_allocator)
        for other in open_panes {
            if active_pane.uuid != other.uuid do append(&ids_to_remove, other.uuid)
        }
        for len(ids_to_remove) > 0 {
            pane_id := pop(&ids_to_remove)

            for other, index in open_panes {
                if other.uuid == pane_id {
                    unordered_remove(&open_panes, index)
                    pane_destroy(other)
                    break
                }
            }
        }

        update_all_pane_textures()
        return true
    case .new_pane_to_the_right:
        result := pane_create()
        switch_to_buffer(result, buffer)
        active_pane = result
        return true
    case .other_pane:
        if len(open_panes) == 1 do return true
        other_pane_index := -1
        for other, index in open_panes {
            if active_pane.uuid == other.uuid {
                other_pane_index = index
                break
            }
        }
        other_pane_index = other_pane_index < len(open_panes) - 1 ? other_pane_index + 1 : 0
        old_pane := active_pane
        active_pane = open_panes[other_pane_index]
        // repaiting the old pane and the new pane
        flag_pane(old_pane, {.Need_Full_Repaint})
        flag_pane(active_pane, {.Need_Full_Repaint})
        return true

    case .undo:
        copy_cursors(pane, buffer)
        undo_done, cursors, pieces := undo(buffer, &buffer.undo, &buffer.redo)

        if !undo_done {
            log.debug("no more history to undo")
            return true
        }

        delete(pane.cursors)
        delete(buffer.pieces)
        pane.cursors = slice.clone_to_dynamic(cursors)
        buffer.pieces = slice.clone_to_dynamic(pieces)
        return true
    case .redo:
        copy_cursors(pane, buffer)
        redo_done, cursors, pieces := undo(buffer, &buffer.redo, &buffer.undo)

        if !redo_done {
            log.debug("no more history to redo")
            return true
        }

        delete(pane.cursors)
        delete(buffer.pieces)
        pane.cursors = slice.clone_to_dynamic(cursors)
        buffer.pieces = slice.clone_to_dynamic(pieces)
        return true

    case .cut_region:
    case .cut_line:
        remove_to(pane, .end_of_line)
        return true
    case .copy_region:
    case .copy_line:
    case .paste:
    case .paste_from_history:
    }

    return false
}

clone_to :: proc(pane: ^Pane, t: Translation) {
    if len(pane.cursors) == 1 {
        cloned := clone_cursor(pane, pane.cursors[0])
        move_to(pane, t, cloned)
    } else if !are_all_cursors_active(pane) {
        cursor_to_clone := get_first_active_cursor(pane)
        cloned := clone_cursor(pane, cursor_to_clone^)
        move_to(pane, t, cloned)
        cursor_to_clone.active = false
        cloned.active = true
    } else {
        pane.cursor_selecting = false
        for &cursor in pane.cursors do cursor.sel = cursor.pos

        switch t {
        case .start: unimplemented()
        case .end: unimplemented()
        case .left: unimplemented()
        case .right: unimplemented()
        case .prev_word: unimplemented()
        case .next_word: unimplemented()
        case .prev_paragraph: unimplemented()
        case .next_paragraph: unimplemented()
        case .beginning_of_line: unimplemented()
        case .end_of_line: unimplemented()
        case .up:
            cursor_to_clone: Cursor
            lo_pos := len(pane.contents)

            for cursor in pane.cursors {
                lo_pos = min(lo_pos, cursor.pos)
                if lo_pos == cursor.pos do cursor_to_clone = cursor
            }
            cloned := clone_cursor(pane, cursor_to_clone)
            move_to(pane, t, cloned)
        case .down:
            cursor_to_clone: Cursor
            hi_pos := 0

            for cursor in pane.cursors {
                hi_pos = max(hi_pos, cursor.pos)
                if hi_pos == cursor.pos do cursor_to_clone = cursor
            }
            cloned := clone_cursor(pane, cursor_to_clone)
            move_to(pane, t, cloned)
        }
    }
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

    if cursor_to_move != nil {
        move_cursor(pane, cursor_to_move, t)
    } else {
        if pane.cursor_selecting {
            select_to(pane, t)
        } else {
            for &cursor in pane.cursors {
                if !cursor.active do continue
                move_cursor(pane, &cursor, t)
            }
        }
    }

    _maybe_merge_overlapping_cursors(pane)
}

select_to :: proc(pane: ^Pane, t: Translation, cursor_to_select: ^Cursor = nil) {
    if cursor_to_select != nil {
        cursor_to_select.pos, _ = translate_position(pane, cursor_to_select.pos, t)
    } else {
        for &cursor in pane.cursors {
            if !cursor.active do continue
            cursor.pos, _ = translate_position(pane, cursor.pos, t)
        }
    }

    _maybe_merge_overlapping_cursors(pane)
}

remove_to :: proc(pane: ^Pane, t: Translation) -> (total_amount_of_removed_characters: int) {
    profiling_start("removing text")
    copy_cursors(pane, pane.buffer)

    for &cursor in pane.cursors {
        if !cursor.active do continue

        if !has_selection(cursor) {
            cursor.pos, _ = translate_position(pane, cursor.pos, t)
        }
    }

    remove_selections(pane)

    profiling_end()
    return
}

remove_selections :: proc(pane: ^Pane) {
    copy_cursors(pane, pane.buffer)

    for &cursor, current_index in pane.cursors {
        if !cursor.active do continue

        if has_selection(cursor) {
            low, high := sorted_cursor(cursor)
            offset := high - low

            if low != high {
                remove_at(pane.buffer, low, offset)
                cursor.pos = low
                cursor.sel = low
            }

            for &other, other_index in pane.cursors {
                if current_index == other_index do continue

                if other.pos > cursor.pos {
                    other.pos -= offset
                    other.sel -= offset
                }
            }
        }
    }

    pane.cursor_selecting = false

    _maybe_merge_overlapping_cursors(pane)
}

insert_at_points :: proc(pane: ^Pane, text: string) -> (total_length_of_inserted_characters: int) {
    profiling_start("inserting text input")
    copy_cursors(pane, pane.buffer)

    remove_selections(pane)

    for &cursor, current_index in pane.cursors {
        if !cursor.active do continue
        offset := insert_at(pane.buffer, cursor.pos, text)
        total_length_of_inserted_characters += offset
        cursor.pos += offset
        cursor.sel = cursor.pos

        for &other, other_index in pane.cursors {
            if current_index == other_index do continue

            if other.pos > cursor.pos {
                other.pos += offset
                other.sel += offset
            }
        }
    }
    profiling_end()
    return
}

insert_newlines_and_indent :: proc(pane: ^Pane) -> (total_length_of_inserted_characters: int) {
    profiling_start("inserting newline and indenting")
    copy_cursors(pane, pane.buffer)

    remove_selections(pane)

    for &cursor, current_index in pane.cursors {
        if !cursor.active do continue
        offset := insert_at(pane.buffer, cursor.pos, "\n")
        cursor.pos += offset
        cursor.sel = cursor.pos
        total_length_of_inserted_characters += offset

        for &other, other_index in pane.cursors {
            if current_index == other_index do continue

            if other.pos > cursor.pos {
                other.pos += offset
                other.sel += offset
            }
        }
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
                    pane.cursors[i].active = true
                    ordered_remove(&pane.cursors, j)
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
