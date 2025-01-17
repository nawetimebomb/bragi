package main

import "core:mem"

CURSOR_BLINK_TIMER :: 1000 / FPS * 60

Cursor :: struct {
    animated       : bool,
    hidden         : bool,
    timer          : u32,
    max_x          : int,
    region_enabled : bool,
    region_start   : Vector2,
    selection_mode : bool,
    x              : int,
    y              : int,
}

Pane :: struct {
    buffer     : ^Text_Buffer,
    cursor     : Cursor,
    dimensions : Vector2,
}

make_pane :: proc(current_pane: ^Pane = nil) {
    new_pane := Pane{}

    if current_pane == nil {
        if len(bragi.buffers) == 0 {
            make_text_buffer("*notes*", 0)
        }

        new_pane.buffer = &bragi.buffers[0]
    } else {
        mem.copy_non_overlapping(&new_pane, current_pane, size_of(Pane))
    }

    append(&bragi.panes, new_pane)
    bragi.focused_pane = len(bragi.panes) - 1
}

// cursor_buffer_to_screen :: proc(pane: ^Pane) {
//     last_line := len(pane.buffer.lines) - 1
//     row := 0

//     for starts_at, index in pane.buffer.lines {
//         past_start_of_row := pane.buffer.cursor >= starts_at
//         on_last_row := index == last_line

//         if past_start_of_row && (on_last_row || pane.buffer.cursor < pane.buffer.lines[index + 1]) {
//             pane.cursor.y = pane.buffer.cursor - starts_at + 1
//             row = index
//             break
//         }
//     }

//     need_to_move := row - (pane.cursor.x - 1)
//     if need_to_move < 0 {
//         balance := min(abs(need_to_move), pane.cursor.x - 1)
//         pane.cursor.x -= balance
//         // pane.line_offset -= abs(need_to_move) - balance
//     } else if need_to_move > 0 {
//         balance := min(need_to_move, pane.dimensions.x - pane.cursor.x)
//         pane.cursor.x += balance
//         // pane.line_offset += need_to_move - balance
//     }
// }

cursor_screen_to_buffer :: proc(pane: ^Pane) {
    // Convert the position of the cursor (v2[x,y]) to a position in the
    // data u8 buffer
}

get_focused_pane :: proc() -> ^Pane {
    return &bragi.panes[bragi.focused_pane]
}

get_buffer_from_current_pane :: proc() -> ^Text_Buffer {
    return get_focused_pane().buffer
}
