package main

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"

Caret_Translation :: enum {
    DOWN, RIGHT, LEFT, UP,
    BUFFER_START,
    BUFFER_END,
    LINE_START,
    LINE_END,
    WORD_START,
    WORD_END,
}


open_file :: proc(p: ^Pane, filepath: string) {
    buffer_found := false

    for &b in bragi.buffers {
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
    if w == .CURRENT {
        other_pane: ^Pane

        for &p1, index in bragi.panes {
            if p.uid != p1.uid {
                other_pane = &p1
                break
            }
        }

        p.mark_for_deletion = true
        bragi.focused_pane_id = other_pane.uid
    } else {
        for &p1 in bragi.panes {
            if p.uid != p1.uid {
                p1.mark_for_deletion = true
            }
        }
    }
}

editor_new_pane :: proc(p: ^Pane) {
    new_pane := pane_init()

    new_pane.buffer = p.buffer
    new_pane.cursor = p.cursor
    result := add(new_pane)

    bragi.focused_pane_id = result.uid
    recalculate_panes()
}

editor_find_file :: proc(target: ^Pane) {

}

toggle_mark_on :: proc(p: ^Pane) {
    log.error("IMPLEMENT")
}
//     if _, ok := p.mode.(Mark_Mode); !ok {
//         set_pane_mode(p, Mark_Mode{
//             begin = p.input.buf.cursor,
//         })
//     }
// }

set_mark :: proc(pane: ^Pane) {
    log.error("IMPLEMENT")
}
//     if type_of(pane.mode) != Mark_Mode {
//         set_pane_mode(pane, Mark_Mode{
//             begin   = pane.input.buf.cursor,
//             marking = true,
//         })
//     } else {
//         set_pane_mode(pane, Edit_Mode{})
//     }
// }

mark_buffer :: proc(pane: ^Pane) {
    log.error("IMPLEMENT")
}
//     pane.input.buf.cursor = 0
//     set_pane_mode(pane, Mark_Mode{
//         begin   = buffer_len(pane.input.buf),
//         marking = true,
//     })
// }

keyboard_quit :: proc(pane: ^Pane) {
    // set_pane_mode(pane, Edit_Mode{})
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
}

// kill_line :: proc(pane: ^Pane, callback: Copy_Proc) {
//     bol, eol := get_line_boundaries(pane.contents.buf[:], pane.input.buf.cursor)
//     line_length := eol - bol

//     if line_length > 0 {
//         set_pane_mode(pane, Mark_Mode{
//             begin = eol,
//         })
//         kill_region(pane, true, callback)
//     } else {
//         delete_forward_char(pane)
//     }
// }

kill_region :: proc(pane: ^Pane, cut: bool, callback: Copy_Proc) {
    log.error("IMPLEMENT")
}

kill_line :: proc(pane: ^Pane, callback: Copy_Proc) {
    log.error("IMPLEMENT")
}
//     marker, ok := pane.mode.(Mark_Mode)

//     if ok {
//         marker := pane.mode.(Mark_Mode)
//         start := min(pane.input.buf.cursor, marker.begin)
//         end   := max(pane.input.buf.cursor, marker.begin)
//         result := string(pane.contents.buf[start:end])

//         if cut {
//             remove(pane.input.buf, end, start - end)
//         }

//         pane.input.buf.cursor = start
//         callback(result)
//         keyboard_quit(pane)
//     }
// }

search :: proc(p: ^Pane) {
    log.error("IMPLEMENT")
}

mouse_set_point :: proc(p: ^Pane, x, y: i32) {
    buffer := p.buffer
    char_width, line_height := get_standard_character_size()
    rel_x := int(x / char_width + p.viewport.x)
    rel_y := int(y / line_height + p.viewport.y)
    p.cursor = canonicalize_coords(transmute([]u8)buffer.str, rel_x, rel_y)
}

mouse_drag_word :: proc(pane: ^Pane, x, y: i32) {
    mouse_set_point(pane, x, y)
    log.error("IMPLEMENT")
    // bow, eow := get_word_boundaries(strings.to_string(pane.contents), pane.input.buf.cursor)

    // pane.input.buf.cursor = eow
    // set_pane_mode(pane, Mark_Mode{
    //     begin = bow,
    // })
}

mouse_drag_line :: proc(pane: ^Pane, x, y: i32) {
    mouse_set_point(pane, x, y)
    log.error("IMPLEMENT")
    // bol, eol := get_line_boundaries(pane.contents.buf[:], pane.input.buf.cursor)

    // pane.input.buf.cursor = eol
    // set_pane_mode(pane, Mark_Mode{
    //     begin = bol,
    // })
}

scroll :: proc(pane: ^Pane, offset: i32) {
    pane.viewport.y += offset
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
    self_insert(p, callback())
    p.should_resync_caret = true
}

self_insert :: proc(p: ^Pane, s: string) {
    cursor := caret_to_buffer_cursor(p.buffer, p.caret.coords)
    p.caret.coords.x += insert(p.buffer, cursor, s)
}

newline :: proc(p: ^Pane) {
    cursor := caret_to_buffer_cursor(p.buffer, p.caret.coords)
    insert(p.buffer, cursor, byte('\n'))
    p.caret.coords.x = 0
    p.caret.coords.y += 1
}

delete_to :: proc(p: ^Pane, t: Caret_Translation) {
    end_pos := caret_to_buffer_cursor(p.buffer, translate(p, t))
    start_pos := caret_to_buffer_cursor(p.buffer, p.caret.coords)
    remove(p.buffer, start_pos, end_pos - start_pos)
    p.should_resync_caret = true
}

move_to :: proc(p: ^Pane, t: Caret_Translation) {
    p.caret.coords = translate(p, t)
}

translate :: proc(p: ^Pane, t: Caret_Translation) -> (pos: Caret_Pos) {
    pos = p.caret.coords
    buffer := p.buffer
    str := buffer.str
    lines_count := len(buffer.lines)

    switch t {
    case .DOWN:
        pos.y += 1
    case .LEFT:
        pos.x -= 1
    case .RIGHT:
        pos.x += 1
    case .UP:
        pos.y -= 1
    case .BUFFER_START:
        pos = { 0, 0 }
    case .BUFFER_END:
        pos = { 0, lines_count - 1 }
    case .LINE_START:
        bol := get_line_start(buffer, pos.y)
        bol_indent := get_line_start_after_indent(buffer, pos.y)
        pos.x = pos.x == 0 ? bol_indent - bol : 0
    case .LINE_END:
        pos.x = get_line_length(buffer, pos.y)
    case .WORD_START:
        s := buffer.str
        x := caret_to_buffer_cursor(buffer, pos)
        for x > 0 && is_whitespace(s[x - 1]) { x -= 1 }
        for x > 0 && !is_whitespace(s[x - 1]) { x -= 1 }
        pos = buffer_cursor_to_caret(buffer, x)
    case .WORD_END:
        s := buffer.str
        x := caret_to_buffer_cursor(buffer, pos)
        for x < len(s) && is_whitespace(s[x])  { x += 1 }
        for x < len(s) && !is_whitespace(s[x]) { x += 1}
        pos = buffer_cursor_to_caret(buffer, x)
    }

    return correct_out_of_bounds_caret(buffer, pos)
}

correct_out_of_bounds_caret :: proc(b: ^Buffer, p: Caret_Pos) -> (pos: Caret_Pos) {
    lines_count := len(b.lines)
    pos = p

    pos.y = clamp(pos.y, 0, lines_count - 1)

    switch {
    case pos.x < 0 && pos.y > 0:
        pos.y -= 1
        pos.x = get_line_length(b, pos.y)
    case pos.x > get_line_length(b, pos.y) && pos.y < lines_count - 1:
        pos.y += 1
        pos.x = 0
    }

    pos.x = clamp(pos.x, 0, get_line_length(b, pos.y))

    return pos
}
