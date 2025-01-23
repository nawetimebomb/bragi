package main

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"

Vector2 :: distinct [2]int

open_file :: proc(filepath: string) {
    buffer_found := false

    for &b in bragi.buffers {
        if b.filepath == filepath {
            bragi.last_pane.buffer = &b
            buffer_found = true
            break
        }
    }

    if !buffer_found {
        bragi.last_pane.buffer = create_buffer_from_file(filepath)
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
    pos := p.buffer.cursor
    buf := p.contents.buf[:]

    if mark {
        toggle_mark_on(p)
    }

    switch t {
    case .beginning_of_buffer:
        pos = 0
    case .beginning_of_line:
        for pos > 0 && !is_newline(buf[pos - 1]) { pos -= 1 }

        if pos == p.buffer.cursor {
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
        prev_line_index := get_previous_line_start_index(buf, pos)
        offset := max(get_current_line_offset(buf, pos), p.caret.max_offset)
        pos = move_to(buf, prev_line_index, offset)

        if offset > p.caret.max_offset {
            p.caret.max_offset = offset
        }
    case .next_line:
        next_line_index := get_next_line_start_index(buf, pos)
        offset := max(get_current_line_offset(buf, pos), p.caret.max_offset)
        pos = move_to(buf, next_line_index, offset)

        if offset > p.caret.max_offset {
            p.caret.max_offset = offset
        }
    case .end_of_buffer:
        pos = buffer_len(p.buffer)
    case .end_of_line:
        for pos < len(buf) && !is_newline(buf[pos]) { pos += 1 }
    }

    p.buffer.cursor = clamp(pos, 0, len(buf))
}

delete_backward_char :: proc(pane: ^Pane) {
    remove(pane.buffer, pane.buffer.cursor, -1)
}

delete_backward_word :: proc(pane: ^Pane) {
    remove(pane.buffer, pane.buffer.cursor, scan_through_similar_runes(
        strings.to_string(pane.contents), .right, pane.buffer.cursor,
    ))
}

delete_forward_char :: proc(pane: ^Pane) {
    remove(pane.buffer, pane.buffer.cursor, 1)
}

delete_forward_word :: proc(pane: ^Pane) {
    remove(pane.buffer, pane.buffer.cursor, scan_through_similar_runes(
        strings.to_string(pane.contents), .right, pane.buffer.cursor,
    ))
}

newline :: proc(pane: ^Pane) {
    insert(pane.buffer, pane.buffer.cursor, byte('\n'))
}

yank :: proc(pane: ^Pane, callback: Paste_Proc) {
    insert(pane.buffer, pane.buffer.cursor, callback())
}

toggle_mark_on :: proc(p: ^Pane) {
    if _, ok := p.mode.(Mark_Mode); !ok {
        set_pane_mode(p, Mark_Mode{
            begin = p.buffer.cursor,
        })
    }
}

set_mark :: proc(pane: ^Pane) {
    if type_of(pane.mode) != Mark_Mode {
        set_pane_mode(pane, Mark_Mode{
            begin   = pane.buffer.cursor,
            marking = true,
        })
    } else {
        set_pane_mode(pane, Edit_Mode{})
    }
}

mark_buffer :: proc(pane: ^Pane) {
    pane.buffer.cursor = 0
    set_pane_mode(pane, Mark_Mode{
        begin   = buffer_len(pane.buffer),
        marking = true,
    })
}

keyboard_quit :: proc(pane: ^Pane) {
    set_pane_mode(pane, Edit_Mode{})
}

undo :: proc(pane: ^Pane) {
    undo_redo(pane.buffer, &pane.buffer.undo, &pane.buffer.redo)
}

redo :: proc(pane: ^Pane) {
    undo_redo(pane.buffer, &pane.buffer.redo, &pane.buffer.undo)
}

kill_current_buffer :: proc(pane: ^Pane) {
    for &b, index in bragi.buffers {
        if &b == pane.buffer {
            destroy_buffer(&b)
            ordered_remove(&bragi.buffers, index)
        }
    }

    get_or_create_buffer("*notes*", 0)
    pane.buffer = &bragi.buffers[len(bragi.buffers) - 1]
}

kill_line :: proc(pane: ^Pane, callback: Copy_Proc) {
    bol, eol := get_line_boundaries(pane.contents.buf[:], pane.buffer.cursor)
    line_length := eol - bol

    if line_length > 0 {
        set_pane_mode(pane, Mark_Mode{
            begin = eol,
        })
        kill_region(pane, true, callback)
    } else {
        delete_forward_char(pane)
    }
}

kill_region :: proc(pane: ^Pane, cut: bool, callback: Copy_Proc) {
    marker, ok := pane.mode.(Mark_Mode)

    if ok {
        marker := pane.mode.(Mark_Mode)
        start := min(pane.buffer.cursor, marker.begin)
        end   := max(pane.buffer.cursor, marker.begin)
        result := string(pane.contents.buf[start:end])

        if cut {
            remove(pane.buffer, end, start - end)
        }

        pane.buffer.cursor = start
        callback(result)
        keyboard_quit(pane)
    }
}

search_backward :: proc(pane: ^Pane) {
    // search, ok := pane.mode.(Search_Mode)

    // if !ok {
    //     query := "impor"
    //     search = Search_Mode{
    //         query     = query,
    //         query_len = len(query),
    //     }

    //     search_buffer(pane.buffer, query, &search.results)
    //     set_pane_mode(pane, search)
    // }

    // #reverse for found, index in search.results {
    //     if pane.buffer.cursor < found + search.query_len {
    //         if index == 0 {
    //             pane.buffer.cursor = search.results[len(search.results) - 1]
    //             break
    //         }

    //         continue
    //     }

    //     pane.buffer.cursor = found
    //     break
    // }
}

search_forward :: proc(p: ^Pane) {
    // search_mode, search_enabled := p.mode.(Search_Mode)

    // if !search_enabled {
    //     start_search(p, .Forward)
    //     return
    // }

    // query := strings.to_string(p.minibuffer)

    // if search_mode.query_len != len(query) {
    //     search_mode.query_len = len(query)
    //     delete(search_mode.results)
    //     search_mode.results = slice.clone(buffer_search(p.buffer, query))
    // }

    // for found, index in search_mode.results {
    //     if p.buffer.cursor > found {
    //         if index == len(search_mode.results) - 1 {
    //             p.buffer.cursor = search_mode.results[0] + search_mode.query_len
    //             break
    //         }

    //         continue
    //     }

    //     p.buffer.cursor = found + search_mode.query_len
    //     break
    // }
}

set_state :: proc(s: Global_State) {
    bragi.global_state = s

    switch t in bragi.global_state {
    case Global_State_None:
        bragi.minibuffer = nil
        strings.builder_reset(&bragi.miniprompt)
    case Global_State_Search:
        bragi.minibuffer = get_or_create_buffer("*search*", 32)
    }
}

search :: proc(p: ^Pane) {
    if _, ok := bragi.global_state.(Global_State_Search); !ok {
        set_state(Global_State_Search{
            target = p,
        })
    }

    // if search_mode, ok := p.mode.(Search_Mode); ok {
    //     results := make([dynamic]int, 0, 10, context.temp_allocator)
    //     s := strings.to_string(p.contents)
    //     query := strings.to_string(p.minibuffer)
    //     initial_length := len(s)
    //     fmt.println(strings.index(s, query))

    //     // for len(query) > 0 {
    //     //     index := strings.index(s, query)
    //     //     if index == -1 { break }
    //     //     append(&results, initial_length - len(s) + index)
    //     //     s = s[index + len(query):]
    //     //     fmt.println(index)
    //     // }
    //     delete(search_mode.results)
    //     search_mode.results = slice.clone(results[:])
    // } else {
    //     log.errorf("Pane is not in Search Mode")
    // }
}

start_search :: proc(pane: ^Pane, direction: Search_Mode_Direction = .Forward) {
    search(pane)
//     search_buffer := get_or_create_buffer("*search*", 32)
//     search_buffer.enable_history = false
//     set_pane_mode(pane, Search_Mode{
//         buffer    = search_buffer,
//         direction = direction,
//     })
}

mouse_set_point :: proc(pane: ^Pane, x, y: i32) {
    set_pane_mode(pane, Edit_Mode{})
    char_width, line_height := get_standard_character_size()
    rel_x := int(x / char_width + pane.camera.x)
    rel_y := int(y / line_height + pane.camera.y)
    pane.buffer.cursor = canonicalize_coords(pane.contents.buf[:], rel_x, rel_y)
}

mouse_drag_word :: proc(pane: ^Pane, x, y: i32) {
    mouse_set_point(pane, x, y)
    bow, eow := get_word_boundaries(strings.to_string(pane.contents), pane.buffer.cursor)

    pane.buffer.cursor = eow
    set_pane_mode(pane, Mark_Mode{
        begin = bow,
    })
}

mouse_drag_line :: proc(pane: ^Pane, x, y: i32) {
    mouse_set_point(pane, x, y)
    bol, eol := get_line_boundaries(pane.contents.buf[:], pane.buffer.cursor)

    pane.buffer.cursor = eol
    set_pane_mode(pane, Mark_Mode{
        begin = bol,
    })
}

scroll :: proc(pane: ^Pane, offset: i32) {
    pane.camera.y += offset
}

save_buffer :: proc(p: ^Pane) {
    buffer_save(p.buffer, p.contents.buf[:])
}
