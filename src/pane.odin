package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:time"

CARET_BLINK_TIMER_DEFAULT :: 0.5

CARET_RESET_TIMEOUT :: 50 * time.Millisecond
CARET_BLINK_TIMEOUT :: 500 * time.Millisecond

Caret_Highlight :: struct {
    start: int,
    length: int,
}

New_Pane_Position :: enum {
    Right, Bottom, Undefined,
}

Caret :: struct {
    hidden:              bool,
    last_keystroke_time: time.Tick,
    last_update_time:    time.Tick,
    last_cursor_pos:     int,
    position:            [2]i32,

    max_x           : int,
}

Edit_Mode :: struct {}

Mark_Mode :: struct {
    begin:   int,
    marking: bool,
}

Search_Mode :: struct {
    query:     string,
    query_len: int,
    results:   [dynamic]int,
}

Pane_Mode :: union #no_nil {
    Edit_Mode,
    Mark_Mode,
    Search_Mode,
}

Pane :: struct {
    buffer:     ^Text_Buffer,
    camera:     [2]i32,
    caret:      Caret,
    dimensions: [2]i32,
    origin:     [2]i32,
    mode:       Pane_Mode,
}

set_pane_mode :: proc(pane: ^Pane, new_mode: Pane_Mode) {
    switch mode in pane.mode {
    case Edit_Mode:
    case Mark_Mode:
    case Search_Mode:
        delete(mode.results)
    }

    pane.mode = new_mode
}

// TODO: Calculate new buffer dimensions and origin
create_pane :: proc(from: ^Pane = nil, pos: New_Pane_Position = .Undefined) {
    new_pane := Pane{}

    if from == nil {
        if len(bragi.buffers) == 0 {
            make_text_buffer("*notes*", 0)
        }

        new_pane.buffer = &bragi.buffers[0]
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
    if pane == nil {
        return
    }

    std_char_size := get_standard_character_size()
    current_cursor_pos := pane.buffer.cursor
    caret := &pane.caret
    now := time.tick_now()

    // TODO: This should update every time create_pane is called
    pane.dimensions = {
        bragi.ctx.window_size.x, bragi.ctx.window_size.y - std_char_size.y * 2,
    }

    page_size_x := pane.dimensions.x / i32(std_char_size.x) - 1
    page_size_y := pane.dimensions.y / i32(std_char_size.y) - 1

    update_text_buffer_time(pane.buffer)

    if time.tick_diff(caret.last_keystroke_time, time.tick_now()) < CARET_RESET_TIMEOUT {
        caret.last_update_time = now
        caret.hidden = false
    }

    if time.tick_diff(caret.last_update_time, now) > CARET_BLINK_TIMEOUT {
        caret.last_update_time = now
        caret.hidden = !caret.hidden
    }

    if force_cursor_update || caret.last_cursor_pos != current_cursor_pos {
        x, y: i32
        buffer_str := entire_buffer_to_string(pane.buffer)

        for c, i in buffer_str {
            if current_cursor_pos == i {
                caret.position = { x, y }

                if x > pane.camera.x + page_size_x {
                    pane.camera.x = x - page_size_x
                } else if x < pane.camera.x {
                    pane.camera.x = x
                }

                if y > pane.camera.y + page_size_y {
                    pane.camera.y = y - page_size_y
                } else if y < pane.camera.y {
                    pane.camera.y = y
                }

                break
            }

            x += 1

            if c == '\n' {
                x = 0
                y += 1
            }
        }
    }

    caret.last_cursor_pos = current_cursor_pos
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
