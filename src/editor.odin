package main

import "core:fmt"
import "core:strings"
import "core:os"

Vector2 :: distinct [2]int
Line    :: string

editor_close :: proc() {
    if bragi.settings.save_desktop_mode {
        // TODO: Save desktop configuration
    }

    for &buf in bragi.buffers {
        for &line in buf.lines { delete(line) }
        delete(buf.lines)
    }

    delete(bragi.buffers)
}

editor_open :: proc() {
    if bragi.settings.save_desktop_mode {
        // TODO: Load desktop configuration
    } else {
        bragi.cbuffer =
            editor_maybe_create_buffer_from_file("C:/Code/bragi/src/main.odin")
        //bragi.cbuffer = editor_create_buffer("*note*")
    }
}

editor_save_file :: proc() {
    buf := bragi.cbuffer
    string_buffer := strings.join(buf.lines[:], "\n")
    data := transmute([]u8)string_buffer
    err := os.write_entire_file_or_err(buf.filepath, data)

    if err != nil {
        fmt.println(data, "Failed to save file", err)
    }

    delete(string_buffer)
}

editor_create_buffer :: proc(buf_name: string, initial_length: int = 1) -> ^Buffer {
    buf := Buffer{ name = buf_name }
    buf.lines = make([dynamic]Line, initial_length, 10)
    append(&bragi.buffers, buf)
    return &bragi.buffers[len(bragi.buffers) - 1]
}

editor_maybe_create_buffer_from_file :: proc(filepath: string) -> ^Buffer {
    for &buf in bragi.buffers {
        if buf.filepath == filepath {
            return &buf
        }
    }

    name := filepath
    data, success := os.read_entire_file_from_filename(filepath, context.temp_allocator)
    str_data := string(data)
    buf := editor_create_buffer(name, 0)
    buf.filepath = filepath

    for line in strings.split_lines_iterator(&str_data) {
        append(&buf.lines, strings.clone(line))
    }

    append(&buf.lines, "")

    return buf
}

is_code_block_open :: proc(line_index: int) -> bool {
    line := bragi.cbuffer.lines[line_index]
    return len(line) > 0 && line[len(line) - 1] == '{'
}

editor_position_cursor :: proc(p: Vector2) {
    buf := bragi.cbuffer
    std_char_size := get_standard_character_size()
    new_pos := Vector2{}
    last_line := len(buf.lines) - 1

    new_pos.x = buf.viewport.x + p.x / std_char_size.x
    new_pos.y = buf.viewport.y + p.y / std_char_size.y

    if new_pos.y > last_line {
        new_pos.y = last_line
    } else if new_pos.y < 0 {
        new_pos.y = 0
    }

    if new_pos.x > len(buf.lines[new_pos.y]) {
        new_pos.x = len(buf.lines[new_pos.y])
    } else if new_pos.x < 0 {
        new_pos.x = 0
    }

    buf.cursor.position = new_pos
}
