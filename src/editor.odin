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

is_code_block_open :: proc(line_index: int) -> bool {
    line := bragi.cbuffer.lines[line_index]
    return len(line) > 0 && line[len(line) - 1] == '{'
}

editor_scroll :: proc(offset: int) {
    buf := bragi.cbuffer
    last_line := len(buf.lines) - 1
    eof_with_offset := last_line - EDITOR_UI_VIEWPORT_OFFSET
    std_char_size := get_standard_character_size()
    page_size := get_page_size()
    new_pos := buf.cursor.position
    new_viewport := buf.viewport

    if page_size.y < last_line {
        new_viewport.y += offset

        if new_viewport.y < 0 {
            new_viewport.y = 0
        } else if new_viewport.y > eof_with_offset {
            new_viewport.y = eof_with_offset
        }

        if new_pos.y > new_viewport.y + page_size.y {
            new_pos.y = new_viewport.y + page_size.y
        } else if new_pos.y < new_viewport.y {
            new_pos.y = new_viewport.y
        }
    }

    buf.cursor.position = new_pos
    buf.viewport = new_viewport
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

editor_move_cursor :: proc(d: Cursor_Direction) {
    // buf := bragi.cbuffer
    // page_size := get_page_size()
    // last_line := len(buf.lines) - 1
    // new_pos := buf.cursor.position

    // switch d {
    // case .Begin_Line:
    //     if new_pos.x == 0 {
    //         for c, i in buf.lines[new_pos.y] {
    //             if c != ' ' {
    //                 new_pos.x = i
    //                 return
    //             }
    //         }
    //     } else {
    //         new_pos.x = 0
    //     }
    // case .Page_Up:
    //     new_pos.y -= page_size.y

    //     if new_pos.y < 0 {
    //         new_pos.y = 0
    //         new_pos.x = 0
    //     } else {
    //         line_len := len(buf.lines[new_pos.y])

    //         if new_pos.x != 0 {
    //             buf.cursor.previous_x = new_pos.x
    //         }

    //         if new_pos.x > line_len {
    //             new_pos.x = line_len
    //         } else {
    //             new_pos.x = buf.cursor.previous_x
    //         }
    //     }
    // case .Page_Down:
    //     new_pos.y += page_size.y

    //     if new_pos.y > last_line {
    //         new_pos.y = last_line
    //         new_pos.x = len(buf.lines[last_line])
    //     } else {
    //         line_len := len(buf.lines[new_pos.y])

    //         if new_pos.x != 0 {
    //             buf.cursor.previous_x = new_pos.x
    //         }

    //         if new_pos.x > line_len {
    //             new_pos.x = line_len
    //         } else {
    //             new_pos.x = buf.cursor.previous_x
    //         }
    //     }
    // }

    // buf.cursor.position = new_pos
}

editor_adjust_viewport_to_cursor :: proc() {
    pos := bragi.cbuffer.cursor.position
    page_size := get_page_size()
    new_viewport := bragi.cbuffer.viewport

    if pos.x > new_viewport.x + page_size.x {
        new_viewport.x = pos.x - page_size.x
    } else if pos.x < new_viewport.x {
        new_viewport.x = pos.x
    }

    if pos.y > new_viewport.y + page_size.y {
        new_viewport.y = pos.y - page_size.y
    } else if pos.y < new_viewport.y {
        new_viewport.y = pos.y
    }

    bragi.cbuffer.viewport = new_viewport
}
