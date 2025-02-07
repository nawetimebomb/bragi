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

Caret_Pos :: [2]int
Caret :: struct {
    blinking:       bool,
    blinking_count: int,
    coords:         Caret_Pos,
    last_keystroke: time.Tick,
    last_offset:    int,
    last_update:    time.Tick,
}

Cursor :: struct {
    head, tail: [2]int,
}

Pane :: struct {
    cursors: [dynamic]Cursor,
    cursor_max_offset: int,
    cursor_blinking: bool,
    cursor_blinking_count: int,
    cursor_last_update: time.Tick,

    last_keystroke: time.Tick,

    id: uuid.Identifier,

    // The pane contents, buffer and its cursor goes here. Cursor lives in the pane so,
    // users can navigate and edit the same buffer in two different panes.
    buffer: ^Buffer,

    // If this pane is marked for deletion, it will be deleted at the end of the frame.
    mark_for_deletion: bool,

    // If the pane should align the caret to the buffer cursor
    should_resync_cursor: bool,

    rect: sdl.Rect,
    texture: ^sdl.Texture,
    // Values that define the UI.
    show_scrollbar: bool,
    // The size of the pane, in relative positions (dimensions / size of character).
    relative_size:  [2]i32,
    // The amount of scrolling the pane has done so far, depending of the caret.
    viewport:       [2]i32,
}

pane_create :: proc(b: ^Buffer = nil, c: [2]int = {}) -> Pane {
    result: Pane
    result.id = uuid.generate_v7()
    result.cursors = make([dynamic]Cursor, 0, 1)
    result.buffer = b
    // NOTE: Panes can have many cursors on the screen, but only one is
    // inherited when the user creates a new pane.
    append(&result.cursors, Cursor{ c, c })
    return result
}

pane_init :: proc() -> Pane {
    p := pane_create()
    return p
}

pane_begin :: proc(p: ^Pane) {
    buffer := p.buffer
    viewport := &p.viewport

    p.relative_size.x = (p.rect.w / char_width) - 2
    p.relative_size.y = (p.rect.h / line_height) - 2

    if buffer  != nil { buffer_update(buffer) }

    if p.should_resync_cursor {
        p.should_resync_cursor = false
        sync_caret_coords(p)
    }

    if should_cursor_reset_blink_timers(p) {
        p.cursor_blinking = false
        p.cursor_blinking_count = 0
        p.cursor_last_update = time.tick_now()
    }

    if should_cursor_blink(p) {
        p.cursor_blinking = !p.cursor_blinking
        p.cursor_blinking_count += 1
        p.cursor_last_update = time.tick_now()
    }

    cursor_head, _ := get_last_cursor(p)
    cursor_x := i32(cursor_head.x)
    cursor_y := i32(cursor_head.y)


    if cursor_x > viewport.x + p.relative_size.x {
        viewport.x = cursor_x - p.relative_size.x
    } else if cursor_x < viewport.x {
        viewport.x = cursor_x
    }

    if cursor_y > viewport.y + p.relative_size.y {
        viewport.y = cursor_y - p.relative_size.y
    } else if cursor_y < viewport.y {
        viewport.y = cursor_y
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

pane_end :: proc(p: ^Pane) {
    if p.mark_for_deletion {
        index_for_this_pane := find_index_for_pane(p)

        if index_for_this_pane == -1 {
            log.errorf("Failed to find the pane: {0}", p)
            return
        }

        if current_pane.id == p.id {
            editor_other_pane(p)
        }

        pane_destroy(p)
        ordered_remove(&open_panes, index_for_this_pane)
        resize_panes()
    }
}

pane_destroy :: proc(p: ^Pane) {
    p.buffer = nil
    delete(p.cursors)
}

resize_panes :: proc() {
    for &p, index in open_panes {
        sdl.DestroyTexture(p.texture)

        w := window_width / i32(len(open_panes))
        h := window_height
        x := w * i32(index)

        if widgets_pane.enabled {
            h = window_height - widgets_pane.rect.h
        }

        p.rect = make_rect(x, 0, w, h)
        p.texture = sdl.CreateTexture(renderer, .RGBA8888, .TARGET, w, h)
    }
}

sync_caret_coords :: proc(p: ^Pane) {
    new_pos := buffer_cursor_to_caret(p.buffer, p.buffer.cursor)
    update_cursor(p, new_pos, new_pos)
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
    return p.cursor_blinking_count < CARET_BLINK_COUNT && time_diff > CARET_BLINK_TIMEOUT
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

create_basic_cursor :: #force_inline proc(p: ^Pane) {
    append(&p.cursors, Cursor{})
}

get_last_cursor :: #force_inline proc(p: ^Pane) -> (head, tail: [2]int) {
    // If there are no cursors alive, create one
    if len(p.cursors) == 0 {
        create_basic_cursor(p)
    }
    assert(len(p.cursors) > 0)
    cursor := p.cursors[len(p.cursors) - 1]
    return cursor.head, cursor.tail
}

update_cursor :: #force_inline proc(p: ^Pane, head, tail: [2]int) {
    cursor := &p.cursors[len(p.cursors) - 1]
    cursor.head = head
    cursor.tail = tail
}

translate_cursor :: proc(p: ^Pane, t: Caret_Translation) -> (pos: [2]int) {
    pos, _ = get_last_cursor(p)
    b := p.buffer
    s := b.str
    lines_count := len(b.lines)

    switch t {
    case .DOWN:
        if pos.y < lines_count - 1 {
            pos.y += 1

            if pos.x > get_line_length(b, pos.y) {
                pos.x = get_line_length(b, pos.y)
            }
        }

        return
    case .UP:
        if pos.y > 0 {
            pos.y -= 1

            if pos.x > get_line_length(b, pos.y) {
                pos.x = get_line_length(b, pos.y)
            }
        }

        return
    case .LEFT:
        pos.x -= 1

        if pos.x < 0 {
            if pos.y > 0 {
                pos.y -= 1
                pos.x = get_line_length(b, pos.y)
            } else {
                pos.x = 0
            }
        }

        return
    case .RIGHT:
        pos.x += 1

        if pos.x > get_line_length(b, pos.y) {
            if pos.y < lines_count - 1 {
                pos.y += 1
                pos.x = 0
            } else {
                pos.x = get_line_length(b, pos.y)
            }
        }

        return
    case .BUFFER_START:
        pos = { 0, 0 }
        return
    case .BUFFER_END:
        pos.y = lines_count - 1
        pos.x = get_line_length(b, pos.y)
        return
    case .LINE_START:
        bol, _ := get_line_boundaries(b, pos.y)
        bol_indent := get_line_start_after_indent(b, pos.y)
        pos.x = pos.x == 0 ? bol_indent - bol : 0
        return
    case .LINE_END:
        pos.x = get_line_length(b, pos.y)
        return
    case .WORD_START:
        s := b.str
        x := caret_to_buffer_cursor(b, pos)
        for x > 0 && is_whitespace(s[x - 1]) { x -= 1 }
        for x > 0 && !is_whitespace(s[x - 1]) { x -= 1 }
        pos = buffer_cursor_to_caret(b, x)
        return
    case .WORD_END:
        s := b.str
        x := caret_to_buffer_cursor(b, pos)
        for x < len(s) && is_whitespace(s[x])  { x += 1 }
        for x < len(s) && !is_whitespace(s[x]) { x += 1}
        pos = buffer_cursor_to_caret(b, x)
        return
    }

    return
}
