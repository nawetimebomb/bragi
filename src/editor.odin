package main

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import "core:time"

editor_do_command :: proc(cmd: Command, p: ^Pane, data: any) {
    p.last_keystroke = time.tick_now()

    #partial switch cmd {
        case .increase_font_size:      increase_font_size()
        case .decrease_font_size:      decrease_font_size()
        case .reset_font_size:         reset_font_size()

        case .find_file:               editor_find_file(p)
        case .switch_buffer:           editor_switch_buffer(p)
        case .search_backward:         editor_search_backward(p)
        case .search_forward:          editor_search_forward(p)
        case .kill_current_buffer:     kill_current_buffer(p)
        case .save_buffer:             save_buffer(p)

        case .delete_this_pane:        editor_close_panes(p, .CURRENT)
        case .delete_other_panes:      editor_close_panes(p, .OTHER)
        case .new_pane_to_the_right:   editor_new_pane(p)
        case .other_pane:              editor_other_pane(p)

        case .undo:                    editor_undo_redo(p, .UNDO)
        case .redo:                    editor_undo_redo(p, .REDO)

        case .kill_region:             log.error("NOT IMPLEMENTED")
        case .kill_line:               editor_delete_to(p, .LINE_END)
        case .kill_ring_save:          log.error("NOT IMPLEMENTED")
        case .yank:                    yank(p, handle_paste)
        case .yank_from_history:       log.error("NOT IMPLEMENTED")

        case .mark_backward_char:      log.error("NOT IMPLEMENTED")
        case .mark_backward_word:      log.error("NOT IMPLEMENTED")
        case .mark_backward_paragraph: log.error("NOT IMPLEMENTED")
        case .mark_forward_char:       log.error("NOT IMPLEMENTED")
        case .mark_forward_word:       log.error("NOT IMPLEMENTED")
        case .mark_forward_paragraph:  log.error("NOT IMPLEMENTED")
        case .mark_rectangle:          log.error("NOT IMPLEMENTED")
        case .mark_set:                editor_set_mark(p)
        case .mark_whole_buffer:       log.error("NOT IMPLEMENTED")

        case .delete_backward_char:    editor_delete_to(p, .LEFT)
        case .delete_backward_word:    editor_delete_to(p, .WORD_START)
        case .delete_forward_char:     editor_delete_to(p, .RIGHT)
        case .delete_forward_word:     editor_delete_to(p, .WORD_END)

        case .beginning_of_buffer:     editor_move_cursor_to(p, .BUFFER_START)
        case .beginning_of_line:       editor_move_cursor_to(p, .LINE_START)
        case .end_of_buffer:           editor_move_cursor_to(p, .BUFFER_END)
        case .end_of_line:             editor_move_cursor_to(p, .LINE_END)
        case .backward_char:           editor_move_cursor_to(p, .LEFT)
        case .backward_word:           editor_move_cursor_to(p, .WORD_START)
        case .forward_char:            editor_move_cursor_to(p, .RIGHT)
        case .forward_word:            editor_move_cursor_to(p, .WORD_END)
        case .next_line:               editor_move_cursor_to(p, .DOWN)
        case .previous_line:           editor_move_cursor_to(p, .UP)

        // Multi-cursor
        case .dupe_next_line:          editor_dupe_cursor_to(p, .DOWN)
        case .dupe_previous_line:      editor_dupe_cursor_to(p, .UP)
        case .delete_cursor:           editor_manage_cursors(p, .DELETE)
        case .switch_cursor:           editor_manage_cursors(p, .SWITCH)
        case .toggle_cursor_group:     editor_manage_cursors(p, .TOGGLE_GROUP)

        case .self_insert:             editor_self_insert(p, data.(string))
    }
}

editor_open_file :: proc(p: ^Pane, filepath: string) {
    buffer_found := false

    for &b in open_buffers {
        if b.filepath == filepath {
            p.buffer = &b
            buffer_found = true
            break
        }
    }

    if !buffer_found {
        p.buffer = create_buffer_from_file(filepath)
    }
}

editor_close_panes :: proc(p: ^Pane, w: enum { CURRENT, OTHER }) {
    if len(open_panes) > 1 {
        if w == .CURRENT {
            for p1, index in open_panes {
                if p1.id == current_pane.id {
                    editor_other_pane(p)
                    pane_destroy(p)
                    ordered_remove(&open_panes, index)
                    break
                }
            }
        } else {
            for &p1, index in open_panes {
                if p1.id != current_pane.id {
                    pane_destroy(&p1)
                    ordered_remove(&open_panes, index)
                }
            }
        }

        resize_panes()
    }
}

editor_new_pane :: proc(p: ^Pane) {
    editor_keyboard_quit(p)
    current_pane = add(pane_create(p.buffer))
}

editor_other_pane :: proc(p: ^Pane) {
    focus_index := find_index_for_pane(p)

    if focus_index == -1 {
        log.errorf("Couldn't find the focused pane")
    }

    focus_index += 1

    if focus_index >= len(open_panes) {
        focus_index = 0
    }

    current_pane = &open_panes[focus_index]
    new_cursor := make_cursor(current_pane.last_cursor_pos)
    delete_all_cursors(current_pane.buffer, new_cursor)
}

editor_find_file :: proc(target: ^Pane) {
    widgets_show(target, .FILES)
}

editor_switch_buffer :: proc(target: ^Pane) {
    widgets_show(target, .BUFFERS)
}

editor_search_backward :: proc(target: ^Pane) {
    widgets_show(target, .SEARCH_REVERSE_IN_BUFFER)
}

editor_search_forward :: proc(target: ^Pane) {
    widgets_show(target, .SEARCH_IN_BUFFER)
}

editor_set_mark :: proc(p: ^Pane) {
    if p.buffer.cursor_selection_mode {
        p.buffer.cursor_selection_mode = false
    } else {
        p.buffer.cursor_selection_mode = true
        pos := get_last_cursor_pos(p.buffer)

        append(&p.markers, Marker{
            buffer = p.buffer,
            pos = pos,
        })
    }
}

kill_current_buffer :: proc(p: ^Pane) {
    if len(open_buffers) > 1 {
        index_of_buffer := -1
        id_of_buffer := p.buffer.id
        replacement_buffer: ^Buffer

        for &b, index in open_buffers {
            if b.id == id_of_buffer {
                index_of_buffer = index
                break
            }
        }

        buffer_destroy(&open_buffers[index_of_buffer])
        ordered_remove(&open_buffers, index_of_buffer)

        for &other_pane in open_panes {
            if other_pane.buffer.id == id_of_buffer {
                other_pane.buffer = &open_buffers[len(open_buffers) - 1]
            }
        }

        reset_viewport(p)
    }
}

kill_region :: proc(pane: ^Pane, cut: bool, callback: Copy_Proc) {
    log.error("IMPLEMENT")
}

editor_switch_to_pane_on_click :: proc(x, y: i32) {
    found, index := find_pane_in_window_coords(x, y)

    if found == nil {
        log.errorf("Pane not found in coordinates {0}, {1}", x, y)
        return
    }

    current_pane = &open_panes[index]
    found.last_keystroke = time.tick_now()
    rel_x, rel_y := get_relative_coords_from_pane(found, x, y)
    mouse_set_point(found, rel_x, rel_y)
}

get_relative_coords_from_pane :: proc(p: ^Pane, x, y: i32) -> (rel_x, rel_y: i32) {
    rel_x = x % p.rect.w
    rel_y = y % p.rect.h
    return
}

mouse_set_point :: proc(p: ^Pane, x, y: i32) {
    coords: Coords
    coords.line = clamp(int(y / line_height) + p.yoffset, 0, len(p.buffer.lines) - 1)

    // Calculate column of the cursor
    line := get_line_text(p.buffer, coords.line)
    size_of_line := get_text_size(font_editor, line)

    if x >= size_of_line + p.size_of_gutter {
        coords.column = len(line)
    } else {
        coords.column = int((x - p.size_of_gutter) / char_width)
    }

    coords_as_buffer_cursor := get_offset_from_coords(p.buffer, coords)
    delete_all_cursors(p.buffer, make_cursor(coords_as_buffer_cursor))
}

mouse_drag_word :: proc(pane: ^Pane, x, y: i32) {
    log.error("IMPLEMENT")
}

mouse_drag_line :: proc(pane: ^Pane, x, y: i32) {
    log.error("IMPLEMENT")
}

scroll :: proc(p: ^Pane, offset: int) {
    MAX_SCROLL_OFFSET :: 7
    lines_count := len(p.buffer.lines)

    if p.visible_lines < lines_count {
        coords := get_last_cursor_pos_as_coords(p.buffer)
        p.yoffset = clamp(p.yoffset + offset, 0, lines_count - MAX_SCROLL_OFFSET)

        if coords.line < p.yoffset || coords.line > p.yoffset + p.visible_lines {
            bol, _ := get_line_boundaries(p.buffer, p.yoffset)
            set_last_cursor_pos(p.buffer, bol + coords.column)
        }
    }
}

save_buffer :: proc(p: ^Pane) {
    buffer_save(p.buffer)
}

editor_undo_redo :: proc(p: ^Pane, a: enum { REDO, UNDO }) {
    if a == .REDO {
        undo_redo(p.buffer, &p.buffer.redo, &p.buffer.undo)
    } else {
        undo_redo(p.buffer, &p.buffer.undo, &p.buffer.redo)
    }
}

yank :: proc(p: ^Pane, callback: Paste_Proc) {
    editor_self_insert(p, callback())
}

editor_self_insert :: proc(p: ^Pane, s: string) {
    insert_string(p.buffer, s)
}

newline :: proc(p: ^Pane) {
    insert_char(p.buffer, '\n')
}

editor_delete_to :: proc(p: ^Pane, t: Cursor_Translation) {
    count: int

    if has_selection(p.buffer) {
        pos, sel, _ := get_last_cursor_decomp(p.buffer)
        count = sel - pos
    } else {
        cursor_at_start := get_last_cursor_pos(p.buffer)
        cursor_after_deletion := translate_cursor(p.buffer, use_last_cursor(p.buffer), t)
        count = cursor_after_deletion - cursor_at_start

        if t == .LINE_END && count == 0 {
            count = 1
        }
    }

    remove(p.buffer, count)
}

editor_move_cursor_to :: proc(p: ^Pane, t: Cursor_Translation) {
    if p.buffer.cursor_selection_mode {
        // If selection mode is enabled, we update all the cursors,
        // as selection has to be done this way.
        // Note, though, that selection will be cleared out if the
        // user tries to duplicate the cursor again. This is intended,
        // as to make a selection, it is best for the user to have
        // all the required cursors in place.
        for &cursor in p.buffer.cursors {
            cursor.pos = translate_cursor(p.buffer, &cursor, t)
        }
    } else if p.buffer.cursor_group_mode {
        // If group mode is enabled, then we move all cursors accordingly
        // but make sure we're not selecting.
        for &cursor in p.buffer.cursors {
            cursor.pos = translate_cursor(p.buffer, &cursor, t)
            cursor.sel = cursor.pos
        }
    } else {
        // Otherwise, if the user is in cursor mode, the user manipulates
        // the last active cursor.
        last_cursor := use_last_cursor(p.buffer)
        last_cursor.pos = translate_cursor(p.buffer, last_cursor, t)
        last_cursor.sel = last_cursor.pos
    }
}

editor_dupe_cursor_to :: proc(p: ^Pane, t: Cursor_Translation) {
    if p.buffer.cursor_selection_mode {
        p.buffer.cursor_selection_mode = false
        pos := get_last_cursor_pos(p.buffer)
        delete_all_cursors(p.buffer, make_cursor(pos))
    }

    p.buffer.interactive_cursors = true
    new_pos := get_last_cursor_pos(p.buffer)
    append(&p.buffer.cursors, make_cursor(new_pos))
    editor_move_cursor_to(p, t)
}

editor_manage_cursors :: proc(p: ^Pane, o: Cursor_Operation) {
    if p.buffer.interactive_cursors && len(p.buffer.cursors) > 1 {
        switch o {
        case .DELETE:
            pop(&p.buffer.cursors)
        case .SWITCH:
            promote_cursor_index(p.buffer, 0)
        case .TOGGLE_GROUP:
            p.buffer.cursor_group_mode = !p.buffer.cursor_group_mode
        }
    }
}

editor_keyboard_quit :: proc(p: ^Pane) {
    last_cursor_pos := get_last_cursor_pos(p.buffer)
    delete_all_cursors(p.buffer, make_cursor(last_cursor_pos))
}
