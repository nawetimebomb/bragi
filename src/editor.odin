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
    return len(bragi.cbuffer.lines) - 1
}

get_page_size :: proc() -> Vector2 {
    window_size := bragi.ctx.window_size
    std_char_size := get_standard_character_size()
    horizontal_page_size := (window_size.x / std_char_size.x) - EDITOR_UI_VIEWPORT_OFFSET
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
        bragi.cbuffer =
            editor_maybe_create_buffer_from_file("C:/Code/bragi/tests/hello.odin")
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
    for &buf in bragi.buffers {
        if buf.filepath == filepath {
            return &buf
        }
    }

    name := filepath
    data, success := os.read_entire_file_from_filename(filepath, context.temp_allocator)
    str_data := string(data)
    buf := editor_create_buffer(name, 0)

    for line in strings.split_lines_iterator(&str_data) {
        append(&buf.lines, strings.clone(line))
    }

    append(&buf.lines, "")

    return buf
}

editor_insert_at_point :: proc(text: cstring) {
    buf := bragi.cbuffer
    pos := &buf.cursor.position

    delete(buf.lines[pos.y])

    builder := strings.builder_make(context.temp_allocator)
    strings.write_string(&builder, buf.lines[pos.y][:pos.x])
    strings.write_string(&builder, string(text))
    strings.write_string(&builder, buf.lines[pos.y][pos.x:])
    buf.lines[pos.y] = strings.clone(strings.to_string(builder))
    pos.x += 1
}

editor_insert_new_line_and_indent :: proc() {
    buf := bragi.cbuffer
    pos := &buf.cursor.position
    left_side_of_cursor := buf.lines[pos.y][:pos.x]
    right_side_of_cursor := buf.lines[pos.y][pos.x:]
    buf.lines[pos.y] = left_side_of_cursor

    pos.y += 1
    pos.x = 0

    inject_at(&buf.lines, pos.y, right_side_of_cursor)
}

editor_delete_char_at_point :: proc(d: CursorDirection) {
    buf := bragi.cbuffer
    pos := &buf.cursor.position
    builder := strings.builder_make(context.temp_allocator)

    if d == .Left {
        pos.x -= 1
    }

    if pos.x < 0 {
        original_string_in_previous_line := buf.lines[pos.y - 1][:]
        rest_of_string_from_removed_line := buf.lines[pos.y][:]
        pos.y -= 1

        if pos.y < 0 {
            pos.y = 0
            pos.x = 0
        } else {
            pos.x = len(buf.lines[pos.y])
        }

        delete(buf.lines[pos.y])
        delete(buf.lines[pos.y + 1])
        ordered_remove(&buf.lines, pos.y + 1)

        strings.write_string(&builder, original_string_in_previous_line)
        strings.write_string(&builder, rest_of_string_from_removed_line)
        buf.lines[pos.y] = strings.clone(strings.to_string(builder))
    } else if pos.x >= eol() {
        original_string_in_current_line := buf.lines[pos.y][:]
        rest_of_string_from_next_line := buf.lines[pos.y + 1][:]

        delete(buf.lines[pos.y])
        delete(buf.lines[pos.y + 1])
        ordered_remove(&buf.lines, pos.y + 1)

        strings.write_string(&builder, original_string_in_current_line)
        strings.write_string(&builder, rest_of_string_from_next_line)
        buf.lines[pos.y] = strings.clone(strings.to_string(builder))
    } else {
        delete(buf.lines[pos.y])

        strings.write_string(&builder, buf.lines[pos.y][:pos.x])
        strings.write_string(&builder, buf.lines[pos.y][pos.x + 1:])
        buf.lines[pos.y] = strings.clone(strings.to_string(builder))
    }
}

editor_move_viewport :: proc(offset: int) {
    buf := bragi.cbuffer
    pos := &buf.cursor.position
    viewport := &buf.viewport
    eof_with_offset := eof() - EDITOR_UI_VIEWPORT_OFFSET
    std_char_size := get_standard_character_size()
    page_size := get_page_size()

    if page_size.y < eof() {
        viewport.y += offset

        if viewport.y < 0 {
            viewport.y = 0
        } else if viewport.y > eof_with_offset {
            viewport.y = eof_with_offset
        }

        if pos.y > viewport.y + page_size.y {
            pos.y = viewport.y + page_size.y
        } else if pos.y < viewport.y {
            pos.y = viewport.y
        }
    }
}

editor_position_cursor :: proc(p: Vector2) {
    buf := bragi.cbuffer
    pos := &buf.cursor.position
    std_char_size := get_standard_character_size()
    viewport := &buf.viewport

    pos.x = viewport.x + p.x / std_char_size.x
    pos.y = viewport.y + p.y / std_char_size.y

    if pos.x > eol() {
        pos.x = eol()
    } else if pos.x < 0 {
        pos.x = 0
    }

    if pos.y > eof() {
        pos.y = eof()
    } else if pos.y < 0 {
        pos.y = 0
    }

    editor_adjust_viewport()
}

editor_move_cursor :: proc(d: CursorDirection) {
    buf := bragi.cbuffer
    cursor := &buf.cursor
    pos := &cursor.position
    viewport := &buf.viewport
    page_size := get_page_size()

    switch d {
    case .Up, .Down:
        if (d == .Up && pos.y > 0) || (d == .Down && pos.y < eof()) {
            pos.y += d == .Up ? -1 : 1

            if pos.x != 0 && pos.x > cursor.previous_x {
                cursor.previous_x = pos.x
            }

            if pos.x <= eol() && cursor.previous_x <= eol() {
                pos.x = cursor.previous_x
            } else {
                pos.x = eol()
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
        pos.y = eof()
        pos.x = eol()
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
            pos.y = eof()
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

    if pos.x > viewport.x + page_size.x {
        viewport.x = pos.x - page_size.x
    } else if pos.x < viewport.x {
        viewport.x = pos.x
    }

    if pos.y > viewport.y + page_size.y {
        viewport.y = pos.y - page_size.y
    } else if pos.y < viewport.y {
        viewport.y = pos.y
    }
}
