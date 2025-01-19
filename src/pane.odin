package main

import "core:log"
import "core:mem"

CARET_BLINK_TIMER_DEFAULT :: 0.5

New_Pane_Position :: enum {
    Right, Bottom, Undefined,
}

Caret :: struct {
    animated        : bool,
    hidden          : bool,
    timer           : f32,
    max_x           : int,
    prev_buffer_pos : int,
    position        : [2]int,
    region_enabled  : bool,
    region_begin    : int,
    selection_mode  : bool,
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
    bragi.focused_pane = len(bragi.panes) - 1
}

get_focused_pane :: proc() -> ^Pane {
    return &bragi.panes[bragi.focused_pane]
}

update_pane :: proc(pane: ^Pane) {
    current_cursor_pos := pane.buffer.cursor

    update_text_buffer_time(pane.buffer)

    if pane.caret.prev_buffer_pos != current_cursor_pos {
        x, y: int
        str := entire_buffer_to_string(pane.buffer)

        for c, i in str {
            if current_cursor_pos == i {
                pane.caret.position = { x, y }
                break
            }

            x += 1

            if c == '\n' {
                x = 0
                y += 1
            }
        }
    }

    pane.caret.prev_buffer_pos = current_cursor_pos
}
