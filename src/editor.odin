package main

Vector2 :: distinct [2]int
Line    :: string

editor_open_file :: proc(filepath: string) {
    buffer_found := false
    pane := get_focused_pane()

    for &b in bragi.buffers {
        if b.filepath == filepath {
            pane.buffer = &b
            buffer_found = true
            break
        }
    }

    if !buffer_found {
        pane.buffer = make_text_buffer_from_file(filepath)
    }
}

beginning_of_buffer :: proc(pane: ^Pane) {
    pane.buffer.cursor = 0
}

beginning_of_line :: proc(pane: ^Pane) {
    start_of_line := line_start(pane.buffer, pane.buffer.cursor)
    end_of_line := line_end(pane.buffer, pane.buffer.cursor)
    new_cursor_position := start_of_line

    if pane.buffer.cursor == start_of_line {
        temp_buffer := make_temp_str_buffer()

        str := flush_buffer_to_custom_string(
            pane.buffer, &temp_buffer, start_of_line, end_of_line,
        )

        for x := 0; x < len(str); x += 1 {
            if str[x] != '\t' && str[x] != ' ' {
                new_cursor_position = start_of_line + x
                break
            }
        }
    }

    pane.buffer.cursor = new_cursor_position
}

end_of_buffer :: proc(pane: ^Pane) {
    pane.buffer.cursor = length_of_buffer(pane.buffer) - 1
}

end_of_line :: proc(pane: ^Pane) {
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
    insert_char_at_point(pane.buffer, '\n')
}

backward_char :: proc(pane: ^Pane) {
    pane.buffer.cursor = max(pane.buffer.cursor - 1, 0)
}

backward_word :: proc(pane: ^Pane) {
    offset := count_backward_words_offset(pane.buffer, pane.buffer.cursor, 1)
    pane.buffer.cursor = max(0, pane.buffer.cursor - offset)
}

forward_char :: proc(pane: ^Pane) {
    pane.buffer.cursor = min(pane.buffer.cursor + 1, length_of_buffer(pane.buffer) - 1)
}

forward_word :: proc(pane: ^Pane) {
    offset := count_forward_words_offset(pane.buffer, pane.buffer.cursor, 1)
    pane.buffer.cursor = min(pane.buffer.cursor + offset, length_of_buffer(pane.buffer) - 1)
}

previous_line :: proc(pane: ^Pane) {
    start_of_line := line_start(pane.buffer, pane.buffer.cursor)
    start_of_prev_line := line_start(pane.buffer, start_of_line - 1)
    x_offset := max(pane.caret.max_x, pane.buffer.cursor - start_of_line)
    str := entire_buffer_to_string(pane.buffer)
    move_cursor_to(pane.buffer, start_of_prev_line, start_of_prev_line + x_offset, true)

    if x_offset > pane.caret.max_x {
        pane.caret.max_x = x_offset
    }
}

next_line :: proc(pane: ^Pane) {
    start_of_line := line_start(pane.buffer, pane.buffer.cursor)
    start_of_next_line := line_end(pane.buffer, pane.buffer.cursor) + 1
    x_offset := max(pane.caret.max_x, pane.buffer.cursor - start_of_line)
    str := entire_buffer_to_string(pane.buffer)
    move_cursor_to(pane.buffer, start_of_next_line, start_of_next_line + x_offset, true)

    if x_offset > pane.caret.max_x {
        pane.caret.max_x = x_offset
    }
}
