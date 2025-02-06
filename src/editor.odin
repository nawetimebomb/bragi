package main

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import "core:time"

Caret_Translation :: enum {
    DOWN, RIGHT, LEFT, UP,
    BUFFER_START,
    BUFFER_END,
    LINE_START,
    LINE_END,
    WORD_START,
    WORD_END,
}

editor_do_command :: proc(cmd: Command, p: ^Pane, data: any) {
    p.caret.last_keystroke = time.tick_now()

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

    for &b in bragi.buffers {
        if b.filepath == filepath {
            p.buffer = &b
            buffer_found = true
            sync_caret_coords(p)
            break
        }
    }

    if !buffer_found {
        p.buffer = create_buffer_from_file(filepath)
        p.caret.coords = {}
    }
}

editor_close_panes :: proc(p: ^Pane, w: enum { CURRENT, OTHER }) {
    if len(bragi.panes) > 1 {
        if w == .CURRENT {
            p.mark_for_deletion = true
        } else {
            for &p1, index in bragi.panes {
                if bragi.focused_index != index {
                    p1.mark_for_deletion = true
                }
            }
        }
    }
}

editor_new_pane :: proc(p: ^Pane) {
    new_pane := pane_init()

    new_pane.buffer = p.buffer
    new_pane.caret = p.caret
    result := add(new_pane)

    bragi.focused_index = len(bragi.panes) - 1
    resize_panes()
}

editor_other_pane :: proc(p: ^Pane) {
    bragi.focused_index += 1

    if bragi.focused_index >= len(bragi.panes) {
        bragi.focused_index = 0
    }
}

editor_find_file :: proc(target: ^Pane) {
    ui_pane_show(target, .FILES)
}

editor_switch_buffer :: proc(target: ^Pane) {
    ui_pane_show(target, .BUFFERS)
}

editor_search_backward :: proc(target: ^Pane) {
    ui_pane_show(target, .SEARCH_REVERSE_IN_BUFFER)
}

editor_search_forward :: proc(target: ^Pane) {
    ui_pane_show(target, .SEARCH_IN_BUFFER)
}

editor_set_buffer_cursor :: proc(p: ^Pane) {
    p.buffer.cursor = caret_to_buffer_cursor(p.buffer, p.caret.coords)
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
    for &b, index in bragi.buffers {
        if &b == p.buffer {
            buffer_destroy(&b)
            ordered_remove(&bragi.buffers, index)
        }
    }

    if len(bragi.buffers) == 0 {
        get_or_create_buffer("*notes*", 0)
    }

    p.buffer = &bragi.buffers[len(bragi.buffers) - 1]
    sync_caret_coords(p)
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

    bragi.focused_index = index
    found.caret.last_keystroke = time.tick_now()
    rel_x, rel_y := get_relative_coords_from_pane(found, x, y)
    mouse_set_point(found, rel_x, rel_y)
}

get_relative_coords_from_pane :: proc(p: ^Pane, x, y: i32) -> (rel_x, rel_y: i32) {
    rel_x = x % p.real_size.x
    rel_y = y % p.real_size.y
    return
}

mouse_set_point :: proc(p: ^Pane, x, y: i32) {
    pos: Caret_Pos
    pos.x = int(x / char_width + p.viewport.x)
    pos.y = int(y / line_height + p.viewport.y)

    editor_set_buffer_cursor(p)
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
        p.viewport.y = clamp(p.viewport.y + offset, 0, lines_count - 10)
        view_y := int(p.viewport.y)
        rel_y := int(p.relative_size.y)

        if p.caret.coords.y < view_y {
            p.caret.coords.y = view_y
        } else if p.caret.coords.y > view_y + rel_y {
            p.caret.coords.y = view_y + rel_y
        }
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

    p.should_resync_caret = success
}

yank :: proc(p: ^Pane, callback: Paste_Proc) {
    editor_self_insert(p, callback())
    p.should_resync_caret = true
}

editor_self_insert :: proc(p: ^Pane, s: string) {
    cursor, _ := get_last_cursor(p)
    buffer_pos := caret_to_buffer_cursor(p.buffer, cursor)
    cursor.x += insert(p.buffer, buffer_pos, s)
    update_cursor(p, cursor, cursor)
}

newline :: proc(p: ^Pane) {
    cursor, _ := get_last_cursor(p)
    buffer_pos := caret_to_buffer_cursor(p.buffer, cursor)
    insert(p.buffer, buffer_pos, byte('\n'))
    cursor = { 0, cursor.y + 1 }
    update_cursor(p, cursor, cursor)
}

delete_to :: proc(p: ^Pane, t: Caret_Translation) {
    cursor_at_start, _ := get_last_cursor(p)
    cursor_after_deletion := translate_cursor(p, t)
    end_pos := caret_to_buffer_cursor(p.buffer, cursor_after_deletion)
    start_pos := caret_to_buffer_cursor(p.buffer, cursor_at_start)
    count := end_pos - start_pos

    remove(p.buffer, start_pos, count)

    if count < 0 {
        update_cursor(p, cursor_after_deletion, cursor_after_deletion)
    }
}

editor_move_to :: proc(p: ^Pane, t: Caret_Translation) {
    new_pos := translate_cursor(p, t)
    update_cursor(p, new_pos, new_pos)
}
