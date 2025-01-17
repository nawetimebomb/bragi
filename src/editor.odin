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

    for &b in bragi.buffers {
        delete(b.data)
        delete(b.lines)
    }
    delete(bragi.buffers)
    delete(bragi.panes)
}

editor_start :: proc() {
    if bragi.settings.save_desktop_mode {
        // TODO: Load desktop configuration
    } else {
        make_pane()
    }

    filepath := "C:/Code/bragi/tests/hello.odin"

    // - Create a pane, with the empty buffer
    // TODO: Should get the last buffer, or clone from an existing pane
    // - Open a test file, dump data to the buffer
    // data, success := os.read_entire_file_from_filename(filepath, context.temp_allocator)

    // parsed_data := make([dynamic]u8, 0, len(data), context.temp_allocator)

    // for c in data {
    //     if c != '\r' {
    //         append(&parsed_data, c)
    //     }
    // }

    // insert_whole_file(new_pane.buffer, parsed_data[:])

    // delete(parsed_data)

    // OLD CODE

}

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

editor_save_file :: proc() {
    fmt.println(string(bragi.panes[bragi.focused_pane].buffer.data))
    fmt.println("------------------")
    fmt.println(entire_buffer_to_string(bragi.panes[bragi.focused_pane].buffer))
    // fmt.println("Trying to save file")
    // buf := bragi.cbuffer
    // string_buffer := strings.join(buf.lines[:], "\n")
    // data := transmute([]u8)string_buffer
    // err := os.write_entire_file_or_err(buf.filepath, data)

    // if err != nil {
    //     fmt.println(data, "Failed to save file", err)
    // }

    // delete(string_buffer)
}

editor_maybe_create_buffer_from_file :: proc(filepath: string) {
    // NEW
    // append(&bragi.buffers, make_text_buffer(0))
    // bragi.panes[0].buffer = &bragi.buffers[len(bragi.buffers) - 1]
    // name := filepath
    // data, success := os.read_entire_file_from_filename(filepath, context.temp_allocator)

    // insert_whole_file(get_buffer_from_current_pane(), data)
}

editor_position_cursor :: proc(wp: Vector2) {
    // buf := bragi.cbuffer
    // std_char_size := get_standard_character_size()
    // new_pos := cursor_canonicalize(wp)
    // last_line := len(buf.lines) - 1

    // if new_pos.y > last_line {
    //     new_pos.y = last_line
    // } else if new_pos.y < 0 {
    //     new_pos.y = 0
    // }

    // if new_pos.x > len(buf.lines[new_pos.y]) {
    //     new_pos.x = len(buf.lines[new_pos.y])
    // } else if new_pos.x < 0 {
    //     new_pos.x = 0
    // }

    // buf.cursor.position = new_pos
}

editor_select :: proc(wp: Vector2) {
    // editor_position_cursor(wp)

    // buf := bragi.cbuffer
    // new_pos := buf.cursor.position

    // start, end := find_word_in_place(buf.lines[new_pos.y], new_pos.x)

    // new_pos.x = end

    // buf.cursor.region_enabled = true
    // buf.cursor.region_start = { start, new_pos.y }
    // buf.cursor.position = new_pos
}
