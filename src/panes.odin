package main

import     "core:fmt"
import     "core:log"
import     "core:strings"
import     "core:time"
import sdl "vendor:sdl2"

// @Description
// Panes follow the concept of "windows" in Emacs. The editor window can separate in
// different panes, and each pane can have its own functionality, or serve as a helper
// for the user to be able to work easily.

// Panes sometimes can contain reference to more than one buffer, because they are meant
// to do processing that require multiple buffers. For example, when doing a search, the
// pane will have a buffer so the user can enter the query, and have a secondary, readonly,
// buffer to show the results of the search. Input will also change in this type of panes
// so they can navigate up and down the results, but also being able to change the query.
// These "search" panes will also have a targeting pane, where the search will be executed,
// and the results will be pulled from.

Caret_Pos :: [2]int
Caret :: struct {
    blinking:       bool,
    blinking_count: int,
    coords:         Caret_Pos,
    last_keystroke: time.Tick,
    last_offset:    int,
    last_update:    time.Tick,
}

Pane :: struct {
    caret: Caret,

    // The pane contents, buffer and its cursor goes here. Cursor lives in the pane so,
    // users can navigate and edit the same buffer in two different panes.
    buffer: ^Buffer,

    // If this pane is marked for deletion, it will be deleted at the end of the frame.
    mark_for_deletion: bool,

    // If the pane should align the caret to the buffer cursor
    should_resync_caret: bool,

    // Values that define the UI.
    show_scrollbar: bool,
    // The size of the pane, in relative positions (dimensions / size of character).
    relative_size:  [2]i32,
    // The size of the pane, in pixels.
    real_size:      [2]i32,
    // The amount of scrolling the pane has done so far, depending of the caret.
    viewport:       [2]i32,
}

pane_init :: proc() -> Pane {
    return  {
        real_size = bragi.ctx.window_size,
    }
}

pane_begin :: proc(p: ^Pane) {
    char_width, line_height := get_standard_character_size()
    buffer := p.buffer
    caret := &p.caret
    viewport := &p.viewport

    p.relative_size.x = (p.real_size.x / char_width) - 2
    p.relative_size.y = (p.real_size.y / line_height) - 2

    if buffer  != nil { buffer_begin(buffer) }

    if p.should_resync_caret {
        p.should_resync_caret = false
        sync_caret_coords(p)
    }

    if should_caret_reset_blink_timers(caret) {
        caret.blinking = false
        caret.blinking_count = 0
        caret.last_update = time.tick_now()
    }

    if should_caret_blink(caret) {
        caret.blinking = !caret.blinking
        caret.blinking_count += 1
        caret.last_update = time.tick_now()
    }

    caret_x := i32(caret.coords.x)
    caret_y := i32(caret.coords.y)

    if caret_x > viewport.x + p.relative_size.x {
        viewport.x = caret_x - p.relative_size.x
    } else if caret_x < viewport.x {
        viewport.x = caret_x
    }

    if caret_y > viewport.y + p.relative_size.y {
        viewport.y = caret_y - p.relative_size.y
    } else if caret_y < viewport.y {
        viewport.y = caret_y
    }
}

pane_end :: proc(p: ^Pane, index: int) {
    if p.buffer  != nil { buffer_end(p.buffer) }

    if p.mark_for_deletion {
        pane_destroy(p)
        ordered_remove(&bragi.panes, index)
        bragi.focused_index = clamp(bragi.focused_index, 0, len(bragi.panes) - 1)
        resize_panes()
    }
}

pane_destroy :: proc(p: ^Pane) {
    p.buffer = nil
}

resize_panes :: proc() {
    // TODO: Move this to the bottom_pane
    BOTTOM_PANE_SIZE :: 6
    _, line_height := get_standard_character_size()
    window_size := bragi.ctx.window_size
    size_y := window_size.y

    if bragi.ui_pane.enabled {
        size_y = window_size.y - (BOTTOM_PANE_SIZE * line_height)
    }

    for &p in bragi.panes {
        p.real_size.x = window_size.x / i32(len(bragi.panes))
        p.real_size.y = size_y
    }

    sdl.DestroyTexture(bragi.ctx.pane_texture)

    bragi.ctx.pane_texture = sdl.CreateTexture(
        bragi.ctx.renderer, .RGBA8888, .TARGET,
        window_size.x / i32(len(bragi.panes)), size_y,
    )
}

sync_caret_coords :: proc(p: ^Pane) {
    p.caret.coords = buffer_cursor_to_caret(p.buffer, p.buffer.cursor)
}

reset_viewport :: proc(p: ^Pane) {
    lines_count := i32(len(p.buffer.lines))

    if p.relative_size.y > lines_count {
        p.viewport = { 0, 0 }
    }
}

should_caret_reset_blink_timers :: #force_inline proc(c: ^Caret) -> bool {
    CARET_RESET_TIMEOUT :: 50 * time.Millisecond
    time_diff := time.tick_diff(c.last_keystroke, time.tick_now())
    return time_diff < CARET_RESET_TIMEOUT
}

should_caret_blink :: #force_inline proc(c: ^Caret) -> bool {
    CARET_BLINK_COUNT   :: 20
    CARET_BLINK_TIMEOUT :: 500 * time.Millisecond
    time_diff := time.tick_diff(c.last_update, time.tick_now())
    return c.blinking_count < CARET_BLINK_COUNT && time_diff > CARET_BLINK_TIMEOUT
}

find_pane_in_window_coords :: proc(x, y: i32) -> (^Pane, int) {
    for &p, index in bragi.panes {
        origin := [2]i32{ p.real_size.x * i32(index), 0 }
        size := [2]i32{ origin.x + p.real_size.x, p.real_size.y }

        if origin.x <= x && size.x > x && origin.y <= y && size.y > y {
            return &p, index
        }
    }

    log.errorf("Couldn't find a valid pane in coords [{0}, {1}]", x, y)
    return nil, 0
}
