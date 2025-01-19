package main

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
    position:            [2]int,
    region_enabled:      bool,
    region_begin:        int,
    selection_mode:      bool,
    search_mode:         bool,
    highlights:          [dynamic]int,
    highlights_len:      int,

    max_x           : int,
}

Pane :: struct {
    buffer          : ^Text_Buffer,
    camera          : Vector2,
    caret           : Caret,
    dimensions      : Vector2,
    origin          : Vector2,
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

update_pane :: proc(pane: ^Pane) {
    if pane == nil {
        return
    }

    current_cursor_pos := pane.buffer.cursor
    caret := &pane.caret
    now := time.tick_now()

    update_text_buffer_time(pane.buffer)

    if time.tick_diff(caret.last_keystroke_time, time.tick_now()) < CARET_RESET_TIMEOUT {
        caret.last_update_time = now
        caret.hidden = false
    }

    if time.tick_diff(caret.last_update_time, now) > CARET_BLINK_TIMEOUT {
        caret.last_update_time = now
        caret.hidden = !caret.hidden
    }

    if caret.last_cursor_pos != current_cursor_pos {
        x, y: int
        str := entire_buffer_to_string(pane.buffer)

        for c, i in str {
            if current_cursor_pos == i {
                caret.position = { x, y }
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
