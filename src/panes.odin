package main

import     "core:encoding/uuid"
import     "core:fmt"
import     "core:log"
import     "core:strings"
import     "core:time"
import sdl "vendor:sdl2"

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
SCROLLING_THRESHOLD :: 2

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
    cursor_showing: bool,
    cursor_blink_count: int,
    cursor_last_update: time.Tick,

    last_keystroke: time.Tick,

    id: uuid.Identifier,

    // The pane contents, buffer and its cursor goes here. Cursor lives in the pane so,
    // users can navigate and edit the same buffer in two different panes.
    buffer: ^Buffer,

    // If this pane is marked for deletion, it will be deleted at the end of the frame.
    mark_for_deletion: bool,

    rect: Rect,
    texture: Texture,
    // Values that define the UI.
    show_scrollbar: bool,
    // The size of the pane, in relative positions (dimensions / size of character).
    relative_size:  [2]i32,
    // The amount of scrolling the pane has done so far, depending of the caret.
    viewport:       [2]i32,
    visible_lines:  i32,
    visible_columns: i32,
    yoffset:        i32,
    xoffset:        i32,
}

pane_create :: proc(b: ^Buffer = nil) -> (result: Pane) {
    result.id = uuid.generate_v7()
    result.buffer = b
    return result
}

pane_init :: proc() -> Pane {
    p := pane_create()
    return p
}

panes_update_draw :: proc() {
    for &p, index in open_panes {
        assert(p.buffer != nil)
        focused := current_pane.id == p.id

        if p.mark_for_deletion {
            if focused {
                editor_other_pane(&p)
            }

            ordered_remove(&open_panes, index)
            resize_panes()
            continue
        }

        buffer_update(p.buffer)

        p.visible_lines = p.rect.h / line_height
        p.visible_columns = p.rect.w / char_width

        if focused {
            if should_cursor_reset_blink_timers(&p) {
                p.cursor_showing = true
                p.cursor_blink_count = 0
                p.cursor_last_update = time.tick_now()
            }

            if should_cursor_blink(&p) {
                p.cursor_showing = !p.cursor_showing
                p.cursor_blink_count += 1
                p.cursor_last_update = time.tick_now()
            }
        } else {
            p.cursor_showing = true
            p.cursor_blink_count = 0
        }

        // { // Make sure the cursor is into view
        //     cursor_head, _ := get_last_cursor(&p)
        //     cursor_x := i32(cursor_head.x)
        //     cursor_y := i32(cursor_head.y)

        //     if cursor_x > p.xoffset + p.visible_columns - SCROLLING_THRESHOLD {
        //         p.xoffset = cursor_x - p.visible_columns + SCROLLING_THRESHOLD
        //     } else if cursor_x < p.xoffset {
        //         p.xoffset = cursor_x
        //     }

        //     if cursor_y > p.yoffset + p.visible_lines - SCROLLING_THRESHOLD {
        //         p.yoffset = cursor_y - p.visible_lines + SCROLLING_THRESHOLD
        //     } else if cursor_y < p.yoffset {
        //         p.yoffset = cursor_y
        //     }
        // }

        render_pane(&p, index, focused)
    }
}

find_index_for_pane :: #force_inline proc(test: ^Pane) -> (result: int) {
    result = -1

    for &p, index in open_panes {
        if test.id == p.id {
            result = index
            return
        }
    }

    return
}

resize_panes :: proc() {
    for &p, index in open_panes {
        w := window_width / i32(len(open_panes))
        h := window_height
        x := w * i32(index)

        if widgets_pane.enabled {
            h = window_height - widgets_pane.rect.h
        }

        p.rect = make_rect(x, 0, w, h)
        p.texture = make_texture(p.texture, .RGBA32, .TARGET, p.rect)
    }
}

reset_viewport :: proc(p: ^Pane) {
    lines_count := i32(len(p.buffer.lines))

    if p.relative_size.y > lines_count {
        p.viewport = { 0, 0 }
    }
}

should_cursor_reset_blink_timers :: #force_inline proc(p: ^Pane) -> bool {
    CARET_RESET_TIMEOUT :: 50 * time.Millisecond
    time_diff := time.tick_diff(p.last_keystroke, time.tick_now())
    return time_diff < CARET_RESET_TIMEOUT
}

should_cursor_blink :: #force_inline proc(p: ^Pane) -> bool {
    CARET_BLINK_COUNT   :: 20
    CARET_BLINK_TIMEOUT :: 500 * time.Millisecond
    time_diff := time.tick_diff(p.cursor_last_update, time.tick_now())
    return p.cursor_blink_count < CARET_BLINK_COUNT && time_diff > CARET_BLINK_TIMEOUT
}

find_pane_in_window_coords :: proc(x, y: i32) -> (^Pane, int) {
    for &p, index in open_panes {
        left   := p.rect.x
        right  := p.rect.x + p.rect.w
        top    := p.rect.y
        bottom := p.rect.y + p.rect.h

        if x >= left && x < right && y >= top && y < bottom {
            return &p, index
        }
    }

    log.errorf("Couldn't find a valid pane in coords [{0}, {1}]", x, y)
    return nil, 0
}
