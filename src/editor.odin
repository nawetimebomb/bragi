package main

import "core:fmt"
import "core:strings"
import "core:os"

// NOTE: Because we have some UI content showing all the time in the editor,
// we have to limit the page size to the space that's actually seen,
// and make sure we scroll earlier.
EDITOR_UI_VIEWPORT_OFFSET :: 2

Vector2 :: distinct [2]int
Line    :: string

CursorDirection :: enum {
    Up, Down, Left, Right,
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

eol :: proc() -> int {
    return len(bragi.cbuffer.lines[bragi.cbuffer.cursor.position.y])
}

eof :: proc() -> int {
    return len(bragi.cbuffer.lines)
}

get_page_size :: proc() -> Vector2 {
    window_size := bragi.ctx.window_size
    std_char_size := get_standard_character_size()
    horizontal_page_size := (window_size.x / std_char_size.y)
    vertical_page_size := (window_size.y / std_char_size.y) - EDITOR_UI_VIEWPORT_OFFSET

    return Vector2{ horizontal_page_size, vertical_page_size }
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
        bragi.cbuffer = editor_maybe_create_buffer_from_file("C:/Code/bragi/src/main.odin")
        //bragi.cbuffer = editor_create_buffer("*note*")
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

editor_move_cursor :: proc(d: CursorDirection) {
    buf := bragi.cbuffer
    cursor := &buf.cursor
    pos := &cursor.position
    viewport := &buf.viewport
    page_size := get_page_size()

    switch d {
    case .Up:
        if pos.y > 0 {
            pos.y -= 1

            if pos.x != 0 {
                cursor.previous_x = pos.x
            }

            if pos.x > eol() {
                pos.x = 0
            } else {
                pos.x = cursor.previous_x
            }
        }
    case .Down:
        if pos.y < eof() {
            pos.y += 1

            if pos.x != 0 {
                cursor.previous_x = pos.x
            }

            if pos.x > eol() {
                pos.x = 0
            } else {
                pos.x = cursor.previous_x
            }
        }
    case .Left:
        if pos.x > 0 {
            pos.x -= 1
        } else {
            if pos.y > 0 {
                pos.y -= 1
                pos.x = eol()
            }
        }
    case .Right:
        if pos.x < eol() {
            pos.x += 1
        } else {
            if pos.y < eof() {
                pos.x = 0
                pos.y += 1
            }
        }
    case .Begin_Line:
        if pos.x == 0 {
            for c, i in buf.lines[pos.y] {
                if c != ' ' {
                    pos.x = i
                    return
                }
            }
        } else {
            pos.x = 0
        }
    case .Begin_File:
        pos.x = 0
        pos.y = 0
    case .End_Line:
        pos.x = eol()
    case .End_File:
        pos.x = eof() - 1
        pos.y = eol()
    case .Page_Up:
        pos.y -= page_size.y

        if pos.y < 0 {
            pos.y = 0
            pos.x = 0
        } else {
            if pos.x != 0 {
                cursor.previous_x = pos.x
            }

            if pos.x > eol() {
                pos.x = eol()
            } else {
                pos.x = cursor.previous_x
            }
        }
    case .Page_Down:
        pos.y += page_size.y

        if pos.y > eof() {
            pos.y = eof() - 1
            pos.x = eol()
        } else {
            if pos.x != 0 {
                cursor.previous_x = pos.x
            }

            if pos.x > eol() {
                pos.x = eol()
            } else {
                pos.x = cursor.previous_x
            }
        }
    }

    editor_adjust_viewport()
}

editor_adjust_viewport :: proc() {
    pos := &bragi.cbuffer.cursor.position
    viewport := &bragi.cbuffer.viewport
    page_size := get_page_size()

    if pos.y > viewport.y + page_size.y {
        viewport.y = pos.y - page_size.y
    } else if pos.y < viewport.y {
        viewport.y = pos.y
    }
}
