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

Cursor_Direction :: enum {
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
}

is_char_a_word_delimiter :: proc(c: rune) -> bool {
    delimiters := " _-.,()[]'\""
    return strings.contains_rune(delimiters, c)
}

find_word_len_with_delimiter :: proc(s: string, p: int, d: Cursor_Direction) -> int {
    delimiters := " _-.,()[]'\""
    hard_delimiters := " _-."

    splits := [?]string{"_", "-", ".", ",", "(", ")", "[", "]", "\"", "'"}
    test_string: string

    if d == .Left {
        test_string := s[:p]
        res := strings.split_multi(test_string, splits[:])
        value := len(res[len(res) - 1]) + 1
        delete(res)
        return value
    } else {
        test_string := s[p:]
        return strings.index_any(test_string, delimiters) + 1
    }
}

calculate_line_indentation :: proc(s: string) -> int {
    for char, index in s {
        if char != ' ' && char != '\t' {
            return index
        }
    }

    return 0
}

editor_delete_word_at_point :: proc(d: Cursor_Direction) {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    line := buf.lines[new_pos.y]
    line_indentation := calculate_line_indentation(line)
    builder := strings.builder_make(context.temp_allocator)
    left_part_of_the_string, rest_of_the_string: string

    if d == .Left && new_pos.x == 0 {
        editor_delete_char_at_point(.Left)
        return
    } else if d == .Right && new_pos.x == len(line) {
        editor_delete_char_at_point(.Right)
        return
    }

    delete(buf.lines[new_pos.y])

    word_len := find_word_len_with_delimiter(line, new_pos.x, d)
    crop_start := new_pos.x + word_len

    if new_pos.x < line_indentation {
        crop_start = line_indentation - new_pos.x
    } else if crop_start > len(line) {
        crop_start = len(line)
    }

    if d == .Left {
        new_pos.x -= word_len

        if new_pos.x < 0 {
            new_pos.x = 0
        }
    }

    strings.write_string(&builder, line[:new_pos.x])
    strings.write_string(&builder, line[crop_start:])

    buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
    buf.cursor.position = new_pos
    buf.modified = true
}

editor_delete_char_at_point :: proc(d: Cursor_Direction) {
    buf := bragi.cbuffer
    new_pos := buf.cursor.position
    last_line := len(buf.lines)
    builder := strings.builder_make(context.temp_allocator)

    if d == .Left {
        new_pos.x -= 1
    }

    if new_pos.x < 0 {
        new_pos.y -= 1

        if new_pos.y < 0 {
            new_pos.y = 0
            new_pos.x = 0
            return
        } else {
            new_pos.x = len(buf.lines[new_pos.y])
        }

        delete(buf.lines[new_pos.y])
        delete(buf.lines[new_pos.y + 1])
        strings.write_string(&builder, buf.lines[new_pos.y][:])
        strings.write_string(&builder, buf.lines[new_pos.y + 1][:])
        ordered_remove(&buf.lines, new_pos.y + 1)
    } else if new_pos.x >= len(buf.lines[new_pos.y]) {
        if new_pos.y + 1 < last_line {
            original_string_in_current_line := buf.lines[new_pos.y][:]
            rest_of_string_from_next_line := buf.lines[new_pos.y + 1][:]

            delete(buf.lines[new_pos.y])
            delete(buf.lines[new_pos.y + 1])
            ordered_remove(&buf.lines, new_pos.y + 1)

            strings.write_string(&builder, original_string_in_current_line)
            strings.write_string(&builder, rest_of_string_from_next_line)
        }
    } else {
        delete(buf.lines[new_pos.y])

        strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
        strings.write_string(&builder, buf.lines[new_pos.y][new_pos.x + 1:])
    }

    buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
    buf.cursor.position = new_pos
    buf.modified = true
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
