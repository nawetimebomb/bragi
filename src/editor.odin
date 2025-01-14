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
    new_pos := buf.cursor.position

    delete(buf.lines[new_pos.y])

    builder := strings.builder_make(context.temp_allocator)
    strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
    strings.write_string(&builder, string(text))
    strings.write_string(&builder, buf.lines[new_pos.y][new_pos.x:])
    buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
    new_pos.x += 1

    buf.cursor.position = new_pos
    buf.modified = true
    editor_adjust_viewport()
}

editor_insert_new_line_and_indent :: proc() {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    left_side_of_cursor := buf.lines[new_pos.y][:new_pos.x]
    right_side_of_cursor := buf.lines[new_pos.y][new_pos.x:]
    buf.lines[new_pos.y] = left_side_of_cursor

    new_pos.y += 1
    new_pos.x = 0

    inject_at(&buf.lines, new_pos.y, right_side_of_cursor)

    buf.cursor.position = new_pos
    buf.modified = true
    editor_adjust_viewport()
}

editor_delete_char_at_point :: proc(d: CursorDirection) {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    builder := strings.builder_make(context.temp_allocator)
    last_line := len(buf.lines)

    if d == .Left {
        new_pos.x -= 1
    }

    if new_pos.x < 0 {
        original_string_in_previous_line := buf.lines[new_pos.y - 1][:]
        rest_of_string_from_removed_line := buf.lines[new_pos.y][:]
        new_pos.y -= 1

        if new_pos.y < 0 {
            new_pos.y = 0
            new_pos.x = 0
        } else {
            new_pos.x = len(buf.lines[new_pos.y])
        }

        delete(buf.lines[new_pos.y])
        delete(buf.lines[new_pos.y + 1])
        ordered_remove(&buf.lines, new_pos.y + 1)

        strings.write_string(&builder, original_string_in_previous_line)
        strings.write_string(&builder, rest_of_string_from_removed_line)
        buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
    } else if new_pos.x >= len(buf.lines[new_pos.y]) {
        if new_pos.y + 1 < last_line {
            original_string_in_current_line := buf.lines[new_pos.y][:]
            rest_of_string_from_next_line := buf.lines[new_pos.y + 1][:]

            delete(buf.lines[new_pos.y])
            delete(buf.lines[new_pos.y + 1])
            ordered_remove(&buf.lines, new_pos.y + 1)

            strings.write_string(&builder, original_string_in_current_line)
            strings.write_string(&builder, rest_of_string_from_next_line)
            buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
        }
    } else {
        delete(buf.lines[new_pos.y])

        strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
        strings.write_string(&builder, buf.lines[new_pos.y][new_pos.x + 1:])
        buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
    }

    buf.cursor.position = new_pos
    buf.modified = true
    editor_adjust_viewport()
}

editor_move_viewport :: proc(offset: int) {
    buf := bragi.cbuffer
    viewport := &buf.viewport
    last_line := len(buf.lines) - 1
    eof_with_offset := last_line - EDITOR_UI_VIEWPORT_OFFSET
    std_char_size := get_standard_character_size()
    page_size := get_page_size()
    new_pos := buf.cursor.position

    if page_size.y < last_line {
        viewport.y += offset

        if viewport.y < 0 {
            viewport.y = 0
        } else if viewport.y > eof_with_offset {
            viewport.y = eof_with_offset
        }

        if new_pos.y > viewport.y + page_size.y {
            new_pos.y = viewport.y + page_size.y
        } else if new_pos.y < viewport.y {
            new_pos.y = viewport.y
        }
    }

    buf.cursor.position = new_pos
}

editor_position_cursor :: proc(p: Vector2) {
    buf := bragi.cbuffer
    std_char_size := get_standard_character_size()
    viewport := &buf.viewport
    new_pos := Vector2{}
    last_line := len(buf.lines) - 1

    new_pos.x = viewport.x + p.x / std_char_size.x
    new_pos.y = viewport.y + p.y / std_char_size.y

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
    editor_adjust_viewport()
}

editor_move_cursor :: proc(d: CursorDirection) {
    buf := bragi.cbuffer
    page_size := get_page_size()
    last_line := len(buf.lines) - 1
    new_pos := buf.cursor.position

    switch d {
    case .Up, .Down:
        if (d == .Up && new_pos.y > 0) || (d == .Down && new_pos.y < last_line) {
            new_pos.y += d == .Up ? -1 : 1
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
    case .Left:
        if new_pos.x > 0 {
            new_pos.x -= 1
        } else {
            if new_pos.y > 0 {
                new_pos.y -= 1
                new_pos.x = len(buf.lines[new_pos.y])
            }
        }
    case .Right:
        if new_pos.x < len(buf.lines[new_pos.y]) {
            new_pos.x += 1
        } else {
            if new_pos.y < last_line {
                new_pos.x = 0
                new_pos.y += 1
            }
        }
    case .Begin_Line:
        if new_pos.x == 0 {
            for c, i in buf.lines[new_pos.y] {
                if c != ' ' {
                    new_pos.x = i
                    return
                }
            }
        } else {
            new_pos.x = 0
        }
    case .Begin_File:
        new_pos.x = 0
        new_pos.y = 0
    case .End_Line:
        new_pos.x = len(buf.lines[new_pos.y])
    case .End_File:
        new_pos.y = last_line
        new_pos.x = len(buf.lines[last_line])
    case .Page_Up:
        new_pos.y -= page_size.y

        if new_pos.y < 0 {
            new_pos.y = 0
            new_pos.x = 0
        } else {
            line_len := len(buf.lines[new_pos.y])

            if new_pos.x != 0 {
                buf.cursor.previous_x = new_pos.x
            }

            if new_pos.x > line_len {
                new_pos.x = line_len
            } else {
                new_pos.x = buf.cursor.previous_x
            }
        }
    case .Page_Down:
        new_pos.y += page_size.y

        if new_pos.y > last_line {
            new_pos.y = last_line
            new_pos.x = len(buf.lines[last_line])
        } else {
            line_len := len(buf.lines[new_pos.y])

            if new_pos.x != 0 {
                buf.cursor.previous_x = new_pos.x
            }

            if new_pos.x > line_len {
                new_pos.x = line_len
            } else {
                new_pos.x = buf.cursor.previous_x
            }
        }
    }

    buf.cursor.position = new_pos
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
