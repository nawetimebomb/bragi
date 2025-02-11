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

CURSOR_BLINK_COUNT   :: 10
CURSOR_BLINK_TIMEOUT :: 500 * time.Millisecond
CURSOR_RESET_TIMEOUT :: 50 * time.Millisecond

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

    // Values that define the UI.
    show_scrollbar: bool,

    rect: Rect,
    texture: Texture,

    last_cursor_pos: int,

    yoffset:         int,
    visible_lines:   int,

    xoffset:         int,
    visible_columns: int,
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

update_and_draw_active_pane :: proc() {
    should_cursor_blink :: proc(p: ^Pane) -> bool {
        return p.cursor_blink_count < CURSOR_BLINK_COUNT &&
            time.tick_diff(p.cursor_last_update, time.tick_now()) > CURSOR_BLINK_TIMEOUT
    }

    p := current_pane

    assert(p.buffer != nil)
    buffer_update(p.buffer)

    p.last_cursor_pos = get_last_cursor_pos(p.buffer)

    if time.tick_diff(p.last_keystroke, time.tick_now()) < CURSOR_RESET_TIMEOUT {
        p.cursor_showing = true
        p.cursor_blink_count = 0
    }

    if should_cursor_blink(p) {
        p.cursor_showing = !p.cursor_showing
        p.cursor_blink_count += 1
        p.cursor_last_update = time.tick_now()
    }

    coords := get_last_cursor_pos_as_coords(p.buffer)

    if coords.column > p.xoffset + p.visible_columns - SCROLLING_THRESHOLD {
        p.xoffset = coords.column - p.visible_columns + SCROLLING_THRESHOLD
    } else if coords.column < p.xoffset {
        p.xoffset = coords.column
    }

    if coords.line > p.yoffset + p.visible_lines - SCROLLING_THRESHOLD {
        p.yoffset = coords.line - p.visible_lines + SCROLLING_THRESHOLD
    } else if coords.line < p.yoffset {
        p.yoffset = coords.line
    }

    colors := bragi.settings.colorscheme_table

    set_renderer_target(p.texture)
    clear_background(colors[.background])

    first_line := p.yoffset
    last_line := min(p.yoffset + p.visible_lines, len(p.buffer.lines) - 1)
    start_offset, _ := get_line_boundaries(p.buffer, first_line)
    _, end_offset := get_line_boundaries(p.buffer, last_line)
    size_of_gutter : i32 = 0
    screen_y := coords.line - p.yoffset
    screen_x := coords.column - p.xoffset

    if bragi.settings.show_line_numbers {
        size_of_gutter += draw_gutter_line_numbers(
            p.rect, first_line, last_line, screen_y,
        )
    } else {
        draw_pane_divider()
    }

    selections := make(
        [dynamic]Range, 0, len(p.buffer.cursors), context.temp_allocator,
    )
    for cursor in p.buffer.cursors {
        // If there's currently no selection, or if the cursor offset,
        // either position or selection, are outside of the offsets
        // available to be shown on the screen at this moment, skip them.
        if cursor.pos == cursor.sel ||
            (cursor.pos < start_offset || cursor.pos > end_offset) &&
            (cursor.sel < start_offset || cursor.sel > end_offset) { continue }

        append(&selections, Range{
            min(cursor.pos, cursor.sel),
            max(cursor.pos, cursor.sel),
        })
    }

    is_colored := p.buffer.major_mode != .Fundamental
    code_lines := make([]Code_Line, last_line - first_line, context.temp_allocator)
    pen := get_pen_for_panes()
    pen.x += size_of_gutter

    for line_number in first_line..<last_line {
        index := line_number - first_line
        code_line := Code_Line{}
        start, end := get_line_boundaries(p.buffer, line_number)
        code_line.start_offset = start
        code_line.line = p.buffer.str[start:end]
        if is_colored { code_line.tokens = p.buffer.tokens[start:end] }
        code_lines[index] = code_line
    }

    draw_code(font_editor, pen, code_lines[:], selections[:], is_colored)

    if p.cursor_showing {
        for cursor in p.buffer.cursors {
            local_coords := get_coords(p.buffer, cursor.pos)

            // Skip rendering cursors that are outside of our view
            if !is_within_the_screen(local_coords, p.yoffset, p.visible_lines) {
                continue
            }

            line := get_line_text(p.buffer, local_coords.line)
            test_str := line[:local_coords.column]
            cursor_rect := make_rect(0, 0, char_width, line_height)
            cursor_rect.y = i32(local_coords.line - p.yoffset) * line_height
            cursor_rect.x = get_width_based_on_text_size(font_editor, test_str, screen_x)
            byte_behind_cursor : byte = ' '

            if cursor.pos < buffer_len(p.buffer) {
                byte_behind_cursor = get_byte_at(p.buffer, cursor.pos)
                if byte_behind_cursor == '\n' { byte_behind_cursor = ' ' }
            }

            draw_cursor(font_editor, pen, cursor_rect, true, byte_behind_cursor)
        }
    }

    draw_modeline(p, true)
    set_renderer_target()
    draw_copy(p.texture, nil, &p.rect)
}

update_and_draw_inactive_panes :: proc(p: ^Pane) {
    assert(p.buffer != nil)
    buffer_update(p.buffer)

    coords := get_coords(p.buffer, p.last_cursor_pos)
    colors := bragi.settings.colorscheme_table

    set_renderer_target(p.texture)
    clear_background(colors[.background])

    first_line := p.yoffset
    last_line := min(p.yoffset + p.visible_lines, len(p.buffer.lines) - 1)
    start_offset, _ := get_line_boundaries(p.buffer, first_line)
    _, end_offset := get_line_boundaries(p.buffer, last_line)
    size_of_gutter : i32 = 0
    screen_y := coords.line - p.yoffset

    if bragi.settings.show_line_numbers {
        size_of_gutter += draw_gutter_line_numbers(
            p.rect, first_line, last_line, screen_y,
        )
    } else {
        draw_pane_divider()
    }

    is_colored := p.buffer.major_mode != .Fundamental
    code_lines := make([]Code_Line, last_line - first_line, context.temp_allocator)
    pen := get_pen_for_panes()
    pen.x += size_of_gutter

    for line_number in first_line..<last_line {
        index := line_number - first_line
        code_line := Code_Line{}
        start, end := get_line_boundaries(p.buffer, line_number)
        code_line.start_offset = start
        code_line.line = p.buffer.str[start:end]
        if is_colored { code_line.tokens = p.buffer.tokens[start:end] }
        code_lines[index] = code_line
    }

    draw_code(font_editor, pen, code_lines[:], {}, is_colored)

    line := get_line_text(p.buffer, coords.line)
    test_str := line[:coords.column]
    cursor_rect := make_rect(0, 0, char_width, line_height)
    cursor_rect.y = i32(screen_y) * line_height
    cursor_rect.x = get_width_based_on_text_size(
        font_editor, test_str, coords.column,
    )

    draw_cursor(font_editor, pen, cursor_rect, false, ' ')
    draw_modeline(p, false)
    set_renderer_target()
    draw_copy(p.texture, nil, &p.rect)
}

is_within_the_screen :: #force_inline proc(
    coords: Coords, first_visible_line, offset: int,
) -> bool {
    return coords.line >= first_visible_line ||
        coords.line < first_visible_line + offset
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
        p.visible_columns = int(p.rect.w / char_width)
        p.visible_lines = int(p.rect.h / line_height)
    }
}

reset_viewport :: proc(p: ^Pane) {
    if p.visible_lines > len(p.buffer.lines) {
        p.yoffset = 0
    }
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

get_pen_for_panes :: #force_inline proc() -> (result: [2]i32) {
    PADDING_FOR_TEXT_CONTENT :: 2
    result.x = PADDING_FOR_TEXT_CONTENT
    return
}
