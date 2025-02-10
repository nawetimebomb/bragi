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
        case .kill_line:               delete_to(p, .LINE_END)
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
        case .mark_set:                log.error("NOT IMPLEMENTED")
        case .mark_whole_buffer:       log.error("NOT IMPLEMENTED")

        case .delete_backward_char:    delete_to(p, .LEFT)
        case .delete_backward_word:    delete_to(p, .WORD_START)
        case .delete_forward_char:     delete_to(p, .RIGHT)
        case .delete_forward_word:     delete_to(p, .WORD_END)

        case .backward_char:           editor_move_to(p, .LEFT)
        case .backward_word:           editor_move_to(p, .WORD_START)
        case .backward_paragraph:      log.error("NOT IMPLEMENTED")
        case .forward_char:            editor_move_to(p, .RIGHT)
        case .forward_word:            editor_move_to(p, .WORD_END)
        case .forward_paragraph:       log.error("NOT IMPLEMENTED")

        case .next_line:               editor_move_to(p, .DOWN)
        case .previous_line:           editor_move_to(p, .UP)

        case .beginning_of_buffer:     editor_move_to(p, .BUFFER_START)
        case .beginning_of_line:       editor_move_to(p, .LINE_START)
        case .end_of_buffer:           editor_move_to(p, .BUFFER_END)
        case .end_of_line:             editor_move_to(p, .LINE_END)

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
            p.mark_for_deletion = true
        } else {
            for &p1, index in open_panes {
                if current_pane != &p1 {
                    p1.mark_for_deletion = true
                }
            }
        }
    }
}

editor_new_pane :: proc(p: ^Pane) {
    new_pane := pane_create(p.buffer)
    current_pane = add(new_pane)
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

toggle_mark_on :: proc(p: ^Pane) {
    log.error("IMPLEMENT")
}

set_mark :: proc(pane: ^Pane) {
    log.error("IMPLEMENT")
}

mark_buffer :: proc(pane: ^Pane) {
    log.error("IMPLEMENT")
}

kill_current_buffer :: proc(p: ^Pane) {
    for &b, index in open_buffers {
        if &b == p.buffer {
            buffer_destroy(&b)
            ordered_remove(&open_buffers, index)
        }
    }

    if len(open_buffers) == 0 {
        get_or_create_buffer("*notes*", 0)
    }

    p.buffer = &open_buffers[len(open_buffers) - 1]
    reset_viewport(p)
}

kill_region :: proc(pane: ^Pane, cut: bool, callback: Copy_Proc) {
    log.error("IMPLEMENT")
}

search :: proc(p: ^Pane) {
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
    b := p.buffer
    coords: Coords
    coords.x = int(x / char_width + p.viewport.x)
    coords.y = int(y / line_height + p.viewport.y)
    delete_all_cursors(b, make_cursor(get_offset_from_coords(b, coords)))
}

mouse_drag_word :: proc(pane: ^Pane, x, y: i32) {
    log.error("IMPLEMENT")
}

mouse_drag_line :: proc(pane: ^Pane, x, y: i32) {
    log.error("IMPLEMENT")
}

scroll :: proc(p: ^Pane, offset: i32) {
    lines_count := i32(len(p.buffer.lines))

    if p.relative_size.y < lines_count {
        p.yoffset = clamp(p.viewport.y + offset, 0, lines_count - 10)
    }
}

save_buffer :: proc(p: ^Pane) {
    buffer_save(p.buffer)
}

editor_undo_redo :: proc(p: ^Pane, a: enum { REDO, UNDO }) {
    success: bool

    if a == .REDO {
        success = undo_redo(p.buffer, &p.buffer.redo, &p.buffer.undo)
    } else {
        success = undo_redo(p.buffer, &p.buffer.undo, &p.buffer.redo)
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

delete_to :: proc(p: ^Pane, t: Cursor_Translation) {
    b := p.buffer
    cursor_at_start := get_last_cursor_pos(b)
    cursor_after_deletion := translate_cursor(b, t)
    count := cursor_after_deletion - cursor_at_start

    remove(b, cursor_at_start, count)
}

editor_move_to :: proc(p: ^Pane, t: Cursor_Translation) {
    b := p.buffer

    for &cursor in b.cursors {
        new_pos := translate_cursor(b, t)
        // TODO: handle selection
        cursor.pos = new_pos
        cursor.sel = new_pos
    }
}
