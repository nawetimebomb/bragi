package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:time"
import "core:strings"

CARET_RESET_TIMEOUT :: 50 * time.Millisecond
CARET_BLINK_TIMEOUT :: 500 * time.Millisecond

New_Pane_Position :: enum {
    Right, Bottom, Undefined,
}

Caret :: struct {
    hidden:              bool,
    max_offset:          int,
    last_keystroke_time: time.Tick,
    last_update_time:    time.Tick,
    last_cursor_pos:     int,
    position:            [2]i32,
}

Edit_Mode :: struct {}

Mark_Mode :: struct {
    begin:   int,
    marking: bool,
}

Search_Mode_Direction :: enum {
    Backward, Forward,
}

Pane_Mode :: union #no_nil {
    Edit_Mode,
    Mark_Mode,
}

Pane :: struct {
    buffer:     ^Buffer,
    contents:   strings.Builder,

    camera:     [2]i32,
    caret:      Caret,
    dimensions: [2]i32,
    origin:     [2]i32,
    mode:       Pane_Mode,
}

set_pane_mode :: proc(pane: ^Pane, new_mode: Pane_Mode) {
    // Make sure to clean-up all allocations when changing state
    switch &mode in pane.mode {
    case Edit_Mode:
    case Mark_Mode:
    }

    // And then initialize the new ones
    switch &mode in new_mode {
    case Edit_Mode:
    case Mark_Mode:
    }

    pane.mode = new_mode
}

// TODO: Calculate new buffer dimensions and origin
create_pane :: proc(from: ^Pane = nil, pos: New_Pane_Position = .Undefined) {
    new_pane := Pane{
        contents   = strings.builder_make(),
    }

    if from == nil {
        new_pane.buffer = get_or_create_buffer("*notes*", 32)
    } else {
        if pos == .Undefined {
            log.errorf("Should define a position for the new pane")
        }

        mem.copy_non_overlapping(&new_pane, from, size_of(Pane))
    }

    append(&bragi.panes, new_pane)
    bragi.current_pane = &bragi.panes[len(bragi.panes) - 1]
    bragi.last_pane    = bragi.current_pane
}

update_pane :: proc(pane: ^Pane, force_cursor_update := false) {
    assert(pane != nil)

    str := strings.to_string(pane.contents)
    char_width, line_height := get_standard_character_size()
    caret := &pane.caret
    now := time.tick_now()

    // TODO: This should update every time create_pane is called
    pane.dimensions = {
        bragi.ctx.window_size.x, bragi.ctx.window_size.y - line_height,
    }

    page_size_x := pane.dimensions.x / char_width - 1
    page_size_y := pane.dimensions.y / line_height - 1

    if time.tick_diff(caret.last_keystroke_time, time.tick_now()) < CARET_RESET_TIMEOUT {
        caret.last_update_time = now
        caret.hidden = false
    }

    if time.tick_diff(caret.last_update_time, now) > CARET_BLINK_TIMEOUT {
        caret.last_update_time = now
        caret.hidden = !caret.hidden
    }

    if len(pane.buffer.lines) > 0 {
        caret.position.y = i32(get_line_number(pane.buffer, pane.buffer.cursor))
        caret.position.x = i32(pane.buffer.cursor - pane.buffer.lines[caret.position.y])

        if caret.position.y > pane.camera.y + page_size_y {
            pane.camera.y = caret.position.y - page_size_y
        } else if caret.position.y < pane.camera.y {
            pane.camera.y = caret.position.y
        }
    }

    // for c, i in str {
    //     if pane.buffer.cursor == i {
    //         caret.position = { x, y }

    //         if x > pane.camera.x + page_size_x {
    //             pane.camera.x = x - page_size_x
    //         } else if x < pane.camera.x {
    //             pane.camera.x = x
    //         }

    //         if y > pane.camera.y + page_size_y {
    //             pane.camera.y = y - page_size_y
    //         } else if y < pane.camera.y {
    //             pane.camera.y = y
    //         }

    //         break
    //     }

    //     x = c == '\n' ? 0 : x + 1
    //     y = c == '\n' ? y + 1 : y
    // }

    //end_buffer(pane.buffer)
}

refresh_panes :: proc() {
    for &pane in bragi.panes {
        update_pane(&pane, true)
    }
}

clicks_on_pane_contents :: proc(x, y: i32) -> bool {
    for &pane in bragi.panes {
        origin := pane.origin
        dims := pane.dimensions

        if origin.x <= x && dims.x > x && origin.y <= y && dims.y > y {
            bragi.current_pane = &pane
            return true
        }
    }

    return false
}
