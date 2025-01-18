package main

import "core:mem"

CARET_BLINK_TIMER_DEFAULT :: 0.5

Caret :: struct {
    animated       : bool,
    hidden         : bool,
    timer          : f32,
    max_x          : int,
    region_enabled : bool,
    region_start   : Vector2,
    selection_mode : bool,
}

Pane :: struct {
    buffer     : ^Text_Buffer,
    caret      : Caret,
    dimensions : Vector2,
    camera     : Vector2,
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

get_focused_pane :: proc() -> ^Pane {
    return &bragi.panes[bragi.focused_pane]
}
