package main

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
        bragi.last_pane.buffer = make_text_buffer_from_file(filepath)
    }
}

beginning_of_buffer :: proc(pane: ^Pane) {
    pane.buffer.cursor = 0
}

beginning_of_line :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }

    sol := line_start(pane.buffer, pane.buffer.cursor)
    eol := line_end(pane.buffer, pane.buffer.cursor)
    new_cursor_position := sol

    if pane.buffer.cursor == sol {
        temp_buffer := make_temp_str_buffer()

        str := flush_buffer_to_custom_string(pane.buffer, &temp_buffer, sol, eol)

        for x := 0; x < len(str); x += 1 {
            if str[x] != '\t' && str[x] != ' ' {
                new_cursor_position = sol + x
                break
            }
        }
    }

    pane.buffer.cursor = new_cursor_position
}

end_of_buffer :: proc(pane: ^Pane) {
    pane.buffer.cursor = length_of_buffer(pane.buffer) - 1
}

end_of_line :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }

    pane.buffer.cursor = line_end(pane.buffer, pane.buffer.cursor)
}

delete_backward_char :: proc(pane: ^Pane) {
    delete_at(pane.buffer, pane.buffer.cursor, -1)
}

delete_backward_word :: proc(pane: ^Pane) {
    offset := count_backward_words_offset(pane.buffer, pane.buffer.cursor, 1)
    delete_at(pane.buffer, pane.buffer.cursor, -offset)
}

delete_forward_char :: proc(pane: ^Pane) {
    delete_at(pane.buffer, pane.buffer.cursor, 1)
}

delete_forward_word :: proc(pane: ^Pane) {
    offset := count_forward_words_offset(pane.buffer, pane.buffer.cursor, 1)
    delete_at(pane.buffer, pane.buffer.cursor, offset)
}

newline :: proc(pane: ^Pane) {
    insert_at(pane.buffer, pane.buffer.cursor, '\n')
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

    pane.buffer.cursor = min(pane.buffer.cursor + 1, length_of_buffer(pane.buffer) - 1)
}

forward_word :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }

    offset := count_forward_words_offset(pane.buffer, pane.buffer.cursor, 1)
    pane.buffer.cursor =
        min(pane.buffer.cursor + offset, length_of_buffer(pane.buffer) - 1)
}

previous_line :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }

    start_of_line := line_start(pane.buffer, pane.buffer.cursor)
    start_of_prev_line := line_start(pane.buffer, start_of_line - 1)

    if start_of_line == 0 {
        pane.buffer.cursor = 0
    } else {
        x_offset := max(pane.caret.max_x, pane.buffer.cursor - start_of_line)
        str := entire_buffer_to_string(pane.buffer)

        move_cursor_to(pane.buffer, start_of_prev_line,
                       start_of_prev_line + x_offset, true)

        if x_offset > pane.caret.max_x {
            pane.caret.max_x = x_offset
        }
    }
}

next_line :: proc(pane: ^Pane, mark: bool) {
    if mark { toggle_mark_on(pane) }

    start_of_line := line_start(pane.buffer, pane.buffer.cursor)
    start_of_next_line := line_end(pane.buffer, pane.buffer.cursor) + 1
    x_offset := max(pane.caret.max_x, pane.buffer.cursor - start_of_line)
    str := entire_buffer_to_string(pane.buffer)
    move_cursor_to(pane.buffer, start_of_next_line, start_of_next_line + x_offset, true)

    if x_offset > pane.caret.max_x {
        pane.caret.max_x = x_offset
    }

    line_len(pane.buffer, pane.buffer.cursor)
}

yank :: proc(pane: ^Pane, callback: Paste_Proc) {
    insert_at(pane.buffer, pane.buffer.cursor, callback())
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
        begin   = length_of_buffer(pane.buffer),
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
            destroy_text_buffer(&b)
            ordered_remove(&bragi.buffers, index)
        }
    }

    if len(bragi.buffers) == 0 {
        make_text_buffer("*notes*", 0)
    }

    pane.buffer = &bragi.buffers[len(bragi.buffers) - 1]
}

kill_line :: proc(pane: ^Pane, callback: Copy_Proc) {
    set_pane_mode(pane, Mark_Mode{
        begin = line_end(pane.buffer, pane.buffer.cursor),
    })
    kill_region(pane, true, callback)
}

kill_region :: proc(pane: ^Pane, cut: bool, callback: Copy_Proc) {
    marker, ok := pane.mode.(Mark_Mode)

    if ok {
        marker := pane.mode.(Mark_Mode)
        start := min(pane.buffer.cursor, marker.begin)
        end   := max(pane.buffer.cursor, marker.begin)
        temp_buffer := make_temp_str_buffer()
        result := flush_buffer_to_custom_string(pane.buffer, &temp_buffer, start, end)

        if cut {
            delete_at(pane.buffer, end, start - end)
        }

        pane.buffer.cursor = start
        callback(result)
        keyboard_quit(pane)
    }
}

search_backward :: proc(pane: ^Pane) {
    search, ok := pane.mode.(Search_Mode)

    if !ok {
        query := "impor"
        search = Search_Mode{
            query     = query,
            query_len = len(query),
        }

        search_buffer(pane.buffer, query, &search.results)
        set_pane_mode(pane, search)
    }

    #reverse for found, index in search.results {
        if pane.buffer.cursor < found + search.query_len {
            if index == 0 {
                pane.buffer.cursor = search.results[len(search.results) - 1]
                break
            }

            continue
        }

        pane.buffer.cursor = found
        break
    }
}

search_forward :: proc(pane: ^Pane) {
    search, ok := pane.mode.(Search_Mode)

    // TODO: Query should be set somewhere else
    if !ok {
        query := "impor"
        search = Search_Mode{
            query     = query,
            query_len = len(query),
        }

        search_buffer(pane.buffer, query, &search.results)
        set_pane_mode(pane, search)
    }

    for found, index in search.results {
        if pane.buffer.cursor > found {
            if index == len(search.results) - 1 {
                pane.buffer.cursor = search.results[0] + search.query_len
                break
            }

            continue
        }

        pane.buffer.cursor = found + search.query_len
        break
    }
}
