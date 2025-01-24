package main

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"

open_file :: proc(filepath: string) {
    buffer_found := false

    for &b in bragi.buffers {
        if b.filepath == filepath {
            bragi.last_pane.input.buf = &b
            buffer_found = true
            break
        }
    }

    if !buffer_found {
        bragi.last_pane.input.buf = create_buffer_from_file(filepath)
    }
}

Translation :: enum {
    beginning_of_buffer,
    beginning_of_line,
    backward_char,
    backward_word,
    forward_char,
    forward_word,
    previous_line,
    next_line,
    end_of_buffer,
    end_of_line,
}

translate :: proc(p: ^Pane, t: Translation, mark := false) {
    pos := p.input.buf.cursor
    buf := p.input.str.buf[:]

    if mark {
        toggle_mark_on(p)
    }

    switch t {
    case .beginning_of_buffer:
        pos = 0
    case .beginning_of_line:
        for pos > 0 && !is_newline(buf[pos - 1]) { pos -= 1 }

        if pos == p.input.buf.cursor {
            for pos < len(buf) && is_whitespace(buf[pos]) { pos += 1 }
        }
    case .backward_char:
        pos -= 1
        for pos > 0 && is_continuation_byte(buf[pos]) { pos -= 1 }
    case .backward_word:
        for pos > 0 && !is_whitespace(buf[pos - 1]) { pos -= 1 }
        for pos > 0 && is_whitespace(buf[pos - 1])  { pos -= 1 }
    case .forward_char:
        pos += 1
        for pos < len(buf) && is_continuation_byte(buf[pos]) { pos += 1 }
    case .forward_word:
        for pos < len(buf) && !is_whitespace(buf[pos]) { pos += 1 }
        for pos < len(buf) && is_whitespace(buf[pos])  { pos += 1 }
    case .previous_line:
        line_number := get_line_number(p.input.buf, pos)

        if line_number == 0 {
            log.debug("Beginning of buffer")
            return
        }

        bol := get_line_offset(p.input.buf, line_number)
        prev_line_number := line_number - 1
        prev_bol := get_line_offset(p.input.buf, prev_line_number)
        pos_offset := pos - bol

        if pos_offset > 0 {
            p.caret.last_offset = pos_offset
        }

        if is_between_line(p.input.buf, prev_line_number, prev_bol + p.caret.last_offset) {
            pos = prev_bol + p.caret.last_offset
        } else if is_between_line(p.input.buf, prev_line_number, prev_bol + pos_offset) {
            pos = prev_bol + pos_offset
        } else {
            pos = get_eol_offset(p.input.buf, prev_line_number)
        }
    case .next_line:
        line_number := get_line_number(p.input.buf, pos)

        if is_last_line(p.input.buf, line_number) {
            log.debug("End of buffer")
            return
        }

        bol := get_line_offset(p.input.buf, line_number)
        next_line_number := line_number + 1
        next_bol := get_line_offset(p.input.buf, next_line_number)
        pos_offset := pos - bol

        if pos_offset > 0 {
            p.caret.last_offset = pos_offset
        }

        if is_between_line(p.input.buf, next_line_number, next_bol + p.caret.last_offset) {
            pos = next_bol + p.caret.last_offset
        } else if is_between_line(p.input.buf, next_line_number, next_bol + pos_offset) {
            pos = next_bol + pos_offset
        } else {
            pos = get_eol_offset(p.input.buf, next_line_number)
        }
    case .end_of_buffer:
        pos = buffer_len(p.input.buf)
    case .end_of_line:
        for pos < len(buf) && !is_newline(buf[pos]) { pos += 1 }
    }

    p.input.buf.cursor = clamp(pos, 0, len(buf))
}

delete_backward_char :: proc(pane: ^Pane) {
    remove(pane.input.buf, pane.input.buf.cursor, -1)
}

delete_backward_word :: proc(p: ^Pane) {
    pos := p.input.buf.cursor
    buf := p.input.str.buf[:]
    for pos > 0 && !is_whitespace(buf[pos - 1]) { pos -= 1 }
    for pos > 0 && is_whitespace(buf[pos - 1])  { pos -= 1 }

    remove(p.input.buf, p.input.buf.cursor, pos - p.input.buf.cursor)
}

delete_forward_char :: proc(pane: ^Pane) {
    remove(pane.input.buf, pane.input.buf.cursor, 1)
}

delete_forward_word :: proc(p: ^Pane) {
    pos := p.input.buf.cursor
    buf := p.input.str.buf[:]
    for pos < len(buf) && !is_whitespace(buf[pos]) { pos += 1 }
    for pos < len(buf) && is_whitespace(buf[pos])  { pos += 1 }
    remove(p.input.buf, p.input.buf.cursor, pos - p.input.buf.cursor)
}

newline :: proc(pane: ^Pane) {
    insert(pane.input.buf, pane.input.buf.cursor, byte('\n'))
}

yank :: proc(pane: ^Pane, callback: Paste_Proc) {
    insert(pane.input.buf, pane.input.buf.cursor, callback())
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

undo :: proc(pane: ^Pane) {
    undo_redo(pane.input.buf, &pane.input.buf.undo, &pane.input.buf.redo)
}

redo :: proc(pane: ^Pane) {
    undo_redo(pane.input.buf, &pane.input.buf.redo, &pane.input.buf.undo)
}

kill_current_buffer :: proc(pane: ^Pane) {
    for &b, index in bragi.buffers {
        if &b == pane.input.buf {
            buffer_destroy(&b)
            ordered_remove(&bragi.buffers, index)
        }
    }

    if len(bragi.buffers) == 0 {
        get_or_create_buffer("*notes*", 0)
    }

    pane.input.buf = &bragi.buffers[len(bragi.buffers) - 1]
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
    char_width, line_height := get_standard_character_size()
    rel_x := int(x / char_width + p.viewport.x)
    rel_y := int(y / line_height + p.viewport.y)
    p.input.buf.cursor = canonicalize_coords(p.input.str.buf[:], rel_x, rel_y)
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
    buffer_save(p.input.buf, p.input.str.buf[:])
}
