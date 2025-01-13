package main

import "core:strings"
import "core:os"

Vector2 :: distinct [2]int
Line    :: string

Cursor :: struct {
    animated       : bool,
    position       : Vector2,
    region_enabled : bool,
    region_start   : Vector2,
}

Buffer :: struct {
    name     : string,
    filepath : string,
    modified : bool,
    readonly : bool,
    lines    : [dynamic]Line,
    cursor   : Cursor,
}

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
        bragi.cbuffer = editor_create_buffer("*note*")
    }
}

editor_create_buffer :: proc(buf_name: string, initial_length: int = 1) -> ^Buffer {
    buf := Buffer{ name = buf_name }
    buf.lines = make([dynamic]Line, initial_length, 10)
    append(&bragi.buffers, buf)
    return &bragi.buffers[len(bragi.buffers) - 1]
}

editor_maybe_create_buffer_from_file :: proc(filepath: string) -> ^Buffer {
    // TODO: find buffer if file was already opened, if not, create a buffer for it
    name := filepath
    data, success := os.read_entire_file_from_filename(filepath, context.temp_allocator)
    str_data := string(data)
    buf := editor_create_buffer(name, 0)

    for line in strings.split_lines_iterator(&str_data) {
        append(&buf.lines, strings.clone(line))
    }

    return buf
}

editor_insert_at_point :: proc(text: cstring) {
    buf := bragi.cbuffer
    cursor := &buf.cursor
    row := cursor.position.y

    delete(buf.lines[row])

    builder := strings.builder_make(context.temp_allocator)
    strings.write_string(&builder, buf.lines[row])
    strings.write_string(&builder, string(text))
    buf.lines[row] = strings.clone(strings.to_string(builder))
    cursor.position.x += 1
}

editor_insert_new_line_and_indent :: proc() {
    buf := bragi.cbuffer
    cursor := &buf.cursor

    cursor.position.y += 1
    cursor.position.x = 0

    if cursor.position.y >= len(buf.lines) {
        // TODO: Add indentantion in the string below
        append(&bragi.cbuffer.lines, "")
    }
}

editor_delete_char_at_point :: proc() {
    buf := bragi.cbuffer
    cursor := &buf.cursor

    cursor.position.x -= 1

    if cursor.position.x < 0 {
        cursor.position.y -= 1

        if cursor.position.y < 0 {
            cursor.position.y = 0
        }

        cursor.position.x = len(buf.lines[buf.cursor.position.y])

        return
    }

    row := cursor.position.y
    buf.lines[row] = buf.lines[row][:len(buf.lines[row]) - 1]
}
