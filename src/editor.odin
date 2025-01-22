package main

import "core:slice"
import "core:strings"

Vector2 :: distinct [2]int
Line    :: string

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

beginning_of_buffer :: proc(pane: ^Pane) {
    pane.buffer.cursor = 0
}

beginning_of_line :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }

    bol, eol := get_line_boundaries(pane.buffer, pane.buffer.cursor)
    new_cursor_position := bol

    if pane.buffer.cursor == bol {
        str := string(pane.builder.buf[bol:eol])

        for x := 0; x < len(str); x += 1 {
            if str[x] != '\t' && str[x] != ' ' {
                new_cursor_position = bol + x
                break
            }
        }
    }

    pane.buffer.cursor = new_cursor_position
}

end_of_buffer :: proc(pane: ^Pane) {
    pane.buffer.cursor = buffer_len(pane.buffer) - 1
}

end_of_line :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }
    _, eol := get_line_boundaries(pane.buffer, pane.buffer.cursor)
    pane.buffer.cursor = eol
}

delete_backward_char :: proc(pane: ^Pane) {
    remove(pane.buffer, pane.buffer.cursor, -1)
}

delete_backward_word :: proc(pane: ^Pane) {
    offset := count_backward_words_offset(pane.buffer, pane.buffer.cursor, 1)
    remove(pane.buffer, pane.buffer.cursor, -offset)
}

delete_forward_char :: proc(pane: ^Pane) {
    remove(pane.buffer, pane.buffer.cursor, 1)
}

delete_forward_word :: proc(pane: ^Pane) {
    offset := count_forward_words_offset(pane.buffer, pane.buffer.cursor, 1)
    remove(pane.buffer, pane.buffer.cursor, offset)
}

newline :: proc(pane: ^Pane) {
    insert(pane.buffer, pane.buffer.cursor, u8('\n'))
}

backward_char :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }

    pane.buffer.cursor = max(pane.buffer.cursor - 1, 0)
}

backward_word :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }

    offset := count_backward_words_offset(pane.buffer, pane.buffer.cursor, 1)
    pane.buffer.cursor = max(0, pane.buffer.cursor - offset)
}

forward_char :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }

    pane.buffer.cursor = min(pane.buffer.cursor + 1, buffer_len(pane.buffer) - 1)
}

forward_word :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }

    offset := count_forward_words_offset(pane.buffer, pane.buffer.cursor, 1)
    pane.buffer.cursor =
        min(pane.buffer.cursor + offset, buffer_len(pane.buffer) - 1)
}

previous_line :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }

    bol, _ := get_line_boundaries(pane.buffer, pane.buffer.cursor)

    if bol == 0 {
        pane.buffer.cursor = 0
    } else {
        prev_bol, _ := get_line_boundaries(pane.buffer, bol - 1)
        x_offset := max(pane.caret.max_x, pane.buffer.cursor - bol)
        move_cursor(pane.buffer, prev_bol, prev_bol + x_offset, true)

        if x_offset > pane.caret.max_x {
            pane.caret.max_x = x_offset
        }
    }
}

next_line :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }

    bol, eol := get_line_boundaries(pane.buffer, pane.buffer.cursor)
    next_bol, _ := get_line_boundaries(pane.buffer, eol + 1)
    x_offset := max(pane.caret.max_x, pane.buffer.cursor - bol)
    move_cursor(pane.buffer, next_bol, next_bol + x_offset, true)

    if x_offset > pane.caret.max_x {
        pane.caret.max_x = x_offset
    }
}

yank :: proc(pane: ^Pane, callback: Paste_Proc) {
    insert(pane.buffer, pane.buffer.cursor, callback())
}

toggle_mark_on :: proc(pane: ^Pane) {
    if type_of(pane.mode) != Mark_Mode {
        set_pane_mode(pane, Mark_Mode{
            begin = pane.buffer.cursor,
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
    bol, eol := get_line_boundaries(pane.buffer, pane.buffer.cursor)
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
        result := string(pane.builder.buf[start:end])

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

search_forward :: proc(pane: ^Pane) {
    search_mode, search_enabled := pane.mode.(Search_Mode)

    if !search_enabled {
        start_search(pane, .Forward)
        return
    }

    query := string(search_mode.builder.buf[:])

    if search_mode.query_len != len(query) {
        search_mode.query_len = len(query)
        delete(search_mode.results)
        search_mode.results = slice.clone(buffer_search(pane.buffer, query))
    }

    for found, index in search_mode.results {
        if pane.buffer.cursor > found {
            if index == len(search_mode.results) - 1 {
                pane.buffer.cursor = search_mode.results[0] + search_mode.query_len
                break
            }

            continue
        }

        pane.buffer.cursor = found + search_mode.query_len
        break
    }
}

start_search :: proc(pane: ^Pane, direction: Search_Mode_Direction = .Forward) {
    set_pane_mode(pane, Search_Mode{
        buffer    = get_or_create_buffer("*search*", 32),
        direction = direction,
    })
}

mouse_set_point :: proc(pane: ^Pane, x, y: i32) {
    set_pane_mode(pane, Edit_Mode{})
    char_size := get_standard_character_size()
    rel_x := int(x / char_size.x + pane.camera.x)
    rel_y := int(y / char_size.y + pane.camera.y)
    canonicalize_coords_to_cursor(pane.buffer, rel_x, rel_y)
}

mouse_drag_word :: proc(pane: ^Pane, x, y: i32) {
    mouse_set_point(pane, x, y)
    bow, eow := get_word_boundaries(pane.buffer, pane.buffer.cursor)

    pane.buffer.cursor = eow
    set_pane_mode(pane, Mark_Mode{
        begin = bow,
    })
}

mouse_drag_line :: proc(pane: ^Pane, x, y: i32) {
    mouse_set_point(pane, x, y)
    bol, eol := get_line_boundaries(pane.buffer, pane.buffer.cursor)

    pane.buffer.cursor = eol
    set_pane_mode(pane, Mark_Mode{
        begin = bol,
    })
}

scroll :: proc(pane: ^Pane, offset: i32) {
    pane.camera.y += offset
}

save_buffer :: proc(pane: ^Pane) {
    buffer_save(pane.buffer)
}
