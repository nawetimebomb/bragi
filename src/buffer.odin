package main

import "core:fmt"
import "core:strings"

Cursor_Direction :: enum {
    Up, Down,
    Backward, Forward,
    Begin_Line, Begin_File,
    End_Line, End_File,
    Page_Up, Page_Down,
}

Cursor :: struct {
    animated       : bool,
    position       : Vector2,
    previous_x     : int,
    region_enabled : bool,
    region_start   : Vector2,
    selection_mode : bool,
}

Buffer :: struct {
    name     : string,
    filepath : string,
    modified : bool,
    readonly : bool,
    lines    : [dynamic]Line,
    cursor   : Cursor,
    viewport : Vector2,
}

buffer_insert_at_point :: proc(text: cstring) {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    builder := strings.builder_make(context.temp_allocator)

    strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
    strings.write_string(&builder, string(text))
    strings.write_string(&builder, buf.lines[new_pos.y][new_pos.x:])

    delete(buf.lines[new_pos.y])
    new_pos.x += 1
    buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
    buf.cursor.position = new_pos
    buf.modified = true
}

// TODO: Currently this function is always adding 4 spaces, but technically
// it should always look at the configuration of the language it's being
// edit, and also, what are the block delimiters.
buffer_newline :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    og_line_index := buf.cursor.position.y
    new_line_indent := get_string_indentation(buf.lines[og_line_index])
    builder := strings.builder_make(context.temp_allocator)

    current_line_content_before_break := buf.lines[og_line_index][:new_pos.x]
    line_content_after_break := buf.lines[og_line_index][new_pos.x:]

    buf.lines[og_line_index] = current_line_content_before_break

    if is_code_block_open(og_line_index) {
        new_line_indent += 4
    }

    for _ in 0..<new_line_indent { strings.write_rune(&builder, ' ') }
    strings.write_string(&builder, line_content_after_break)
    inject_at(&buf.lines, og_line_index + 1, strings.clone(strings.to_string(builder)))

    new_pos.y += 1
    new_pos.x = len(buf.lines[new_pos.y])

    buf.cursor.position = new_pos
    buf.modified = true
}

buffer_delete_word_backward :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    line_indent := get_string_indentation(buf.lines[new_pos.y])
    builder := create_string_builder()

    if new_pos.x == 0 {
        buffer_delete_char_backward()
    } else {
        new_pos.x = find_backward_word(buf.lines[new_pos.y], new_pos.x)

        if new_pos.x <= line_indent {
            new_pos.x = 0
        }

        strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
        strings.write_string(&builder, buf.lines[new_pos.y][buf.cursor.position.x:])

        delete(buf.lines[new_pos.y])
        buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
        buf.cursor.position = new_pos
        buf.modified = true
    }
}

buffer_delete_word_forward :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    line_indent := get_string_indentation(buf.lines[new_pos.y])
    builder := create_string_builder()

    if new_pos.x == len(buf.lines[new_pos.y]) {
        buffer_delete_char_forward()
    } else {
        point_to_cut := find_forward_word(buf.lines[new_pos.y], new_pos.x)

        if new_pos.x < line_indent {
            point_to_cut = line_indent
        }

        strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
        strings.write_string(&builder, buf.lines[new_pos.y][point_to_cut:])

        delete(buf.lines[new_pos.y])
        buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
        buf.cursor.position = new_pos
        buf.modified = true
    }
}

buffer_delete_char_backward :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    builder := create_string_builder()

    new_pos.x -= 1

    if new_pos.x < 0 {
        new_pos.y -= 1

        if new_pos.y < 0 {
            new_pos.y = 0
            new_pos.x = 0
        } else {
            new_pos.x = len(buf.lines[new_pos.y])

            strings.write_string(&builder, buf.lines[new_pos.y][:])
            strings.write_string(&builder, buf.lines[new_pos.y + 1][:])
            delete(buf.lines[new_pos.y])
            delete(buf.lines[new_pos.y + 1])
            ordered_remove(&buf.lines, new_pos.y + 1)
            buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
        }
    } else {
        strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
        strings.write_string(&builder, buf.lines[new_pos.y][new_pos.x + 1:])
        delete(buf.lines[new_pos.y])
        buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
    }

    buf.cursor.position = new_pos
    buf.modified = true
}

buffer_delete_char_forward :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    builder := create_string_builder()

    if new_pos.x >= len(buf.lines[new_pos.y]) {
        if new_pos.y + 1 < len(buf.lines) {
            strings.write_string(&builder, buf.lines[new_pos.y][:])
            strings.write_string(&builder, buf.lines[new_pos.y + 1][:])
            delete(buf.lines[new_pos.y])
            delete(buf.lines[new_pos.y + 1])
            ordered_remove(&buf.lines, new_pos.y + 1)
            buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
        }
    } else {
        strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
        strings.write_string(&builder, buf.lines[new_pos.y][new_pos.x + 1:])
        delete(buf.lines[new_pos.y])
        buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
    }

    buf.cursor.position = new_pos
    buf.modified = true
}

buffer_backward_char :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position

    if new_pos.x > 0 {
        new_pos.x -= 1
    } else {
        if new_pos.y > 0 {
            new_pos.y -= 1
            new_pos.x = len(buf.lines[new_pos.y])
        }
    }

    buf.cursor.position = new_pos
}

buffer_backward_paragraph :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position

    for y := new_pos.y - 1; y > 0; y -= 1 {
        if len(buf.lines[y]) == 0 {
            new_pos.y = y
            new_pos.x = 0
            break
        }
    }

    if new_pos.y == buf.cursor.position.y {
        new_pos.y = 0
        new_pos.x = 0
    }

    buf.cursor.position = new_pos
}

buffer_backward_word :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    prev_word_offset := find_backward_word(buf.lines[new_pos.y], new_pos.x)

    if new_pos.x == 0 {
        if new_pos.y > 0 {
            new_pos.y -= 1
            new_pos.x = len(buf.lines[new_pos.y])
        }
    } else {
        new_pos.x = prev_word_offset
    }

    buf.cursor.position = new_pos
}

buffer_forward_char :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    last_line := len(buf.lines) - 1

    if new_pos.x < len(buf.lines[new_pos.y]) {
        new_pos.x += 1
    } else {
        if new_pos.y < last_line {
            new_pos.x = 0
            new_pos.y += 1
        }
    }

    buf.cursor.position = new_pos
}

buffer_forward_paragraph :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position

    for y := new_pos.y + 1; y < len(buf.lines); y += 1 {
        if len(buf.lines[y]) == 0 {
            new_pos.y = y
            new_pos.x = 0
            break
        }
    }

    if new_pos.y == buf.cursor.position.y {
        new_pos.y = len(buf.lines) - 1
        new_pos.x = 0
    }

    buf.cursor.position = new_pos
}

buffer_forward_word :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    next_word_offset := find_forward_word(buf.lines[new_pos.y], new_pos.x)
    last_line := len(buf.lines) - 1

    if new_pos.x >= len(buf.lines[new_pos.y]) {
        if new_pos.y < last_line {
            new_pos.y += 1
            new_pos.x = 0
        }
    } else {
        new_pos.x = next_word_offset
    }

    buf.cursor.position = new_pos
}

buffer_previous_line :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position

    if new_pos.y == 0 {
        new_pos.x = 0
        buf.cursor.previous_x = 0
    } else {
        new_pos.y -= 1
        line_len := len(buf.lines[new_pos.y])

        if new_pos.x != 0 && new_pos.x > buf.cursor.previous_x {
            buf.cursor.previous_x = new_pos.x
        }

        if new_pos.x <= line_len && buf.cursor.previous_x <= line_len {
            new_pos.x = buf.cursor.previous_x
        } else {
            new_pos.x = line_len
        }
    }

    buf.cursor.position = new_pos
}

buffer_next_line :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    last_line := len(buf.lines) - 1

    if new_pos.y < last_line {
        new_pos.y += 1
        line_len := len(buf.lines[new_pos.y])

        if new_pos.x != 0 && new_pos.x > buf.cursor.position.x {
            buf.cursor.previous_x = new_pos.x
        }

        if new_pos.x <= line_len && buf.cursor.previous_x <= line_len {
            new_pos.x = buf.cursor.previous_x
        } else {
            new_pos.x = line_len
        }
    }

    buf.cursor.position = new_pos
}

buffer_beginning_of_buffer :: proc() {
    buf := bragi.cbuffer
    buf.cursor.position = { 0, 0 }
}

buffer_beginning_of_line :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position

    if new_pos.x == 0 {
        new_pos.x = get_string_indentation(buf.lines[new_pos.y])
    } else {
        new_pos.x = 0
    }

    buf.cursor.position = new_pos
}

buffer_end_of_buffer :: proc() {
    buf := bragi.cbuffer
    buf.cursor.position = { 0, len(buf.lines) - 1 }
}

buffer_end_of_line :: proc() {
    buf := bragi.cbuffer
    buf.cursor.position.x = len(buf.lines[buf.cursor.position.y])
}
