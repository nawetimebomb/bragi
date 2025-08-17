package main

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

CURSOR_BLINK_MAX_COUNT :: 6
CURSOR_BLINK_TIMEOUT   :: 500 * time.Millisecond
CURSOR_RESET_TIMEOUT   :: 100 * time.Millisecond

MINIMUM_GUTTER_PADDING     :: 3
GUTTER_LINE_NUMBER_JUSTIFY :: 2

Pane_Flags :: bit_set[Pane_Flag; u8]

Pane_Mode :: enum u8 {
    Line_Wrappings,
}

Pane_Flag :: enum u8 {
    Need_Full_Repaint,
}

Cursor_Mode :: enum u8 {
    Interactive = 0, // multiple cursors, controlling one
    Group       = 1, // multiple cursors, controlling all
    Selection   = 2, // doing selection, play with multiple cursors
}

Translation :: enum u16 {
    start, end,
    down, left, right, up,
    prev_word, next_word,
    prev_paragraph, next_paragraph,
    beginning_of_line, end_of_line,
}

Pane :: struct {
    cursors:             [dynamic]Cursor,
    cursor_modes:        bit_set[Cursor_Mode; u8],
    cursor_showing:      bool,
    cursor_blink_count:  int,
    cursor_blink_timer:  time.Tick,

    buffer:              ^Buffer,
    contents:            strings.Builder,
    line_starts:         [dynamic]int,
    wrapped_line_starts: [dynamic]int,
    local_font_size:     i32,
    font:                ^Font,

    // TODO(nawe) maybe combine?
    modes:               bit_set[Pane_Mode; u8],
    flags:               Pane_Flags,

    // rendering stuff
    rect:                Rect,
    texture:             ^Texture,
    x_offset:            int,
    visible_columns:     int,
    y_offset:            int,
    visible_rows:        int,
}

Cursor :: struct {
    active: bool,
    pos:    int,
    sel:    int,

    // NOTE(nawe) like Emacs, I want to align the cursor to the last
    // largest offset if possible, this is very helpful when
    // navigating up and down a buffer. If the current row is larger
    // than last_column, the cursor will be positioned at last_cursor,
    // if it is smaller, it will be positioned at the end of the
    // row. Some commands will reset this value to -1.
    last_column: int,
}

Code_Line :: struct {
    line:               string,
    line_is_wrapped:    bool, // this line continues on the next line
    start_offset:       int,
    //tokens:          []Token_Kind,
}

pane_create :: proc(buffer: ^Buffer = nil) -> ^Pane {
    log.debug("creating new pane")
    result := new(Pane)

    result.cursor_showing = true
    result.cursor_blink_count = 0
    result.cursor_blink_timer = time.tick_now()
    add_cursor(result)

    if buffer == nil {
        result.buffer = buffer_get_or_create_empty()
    } else {
        result.buffer = buffer
    }

    result.local_font_size = i32(settings.editor_font_size)

    append(&open_panes, result)
    update_all_pane_textures()
    return result
}

pane_destroy :: proc(pane: ^Pane) {
    pane.buffer = nil
    strings.builder_destroy(&pane.contents)
    delete(pane.cursors)
    delete(pane.line_starts)
    delete(pane.wrapped_line_starts)
    free(pane)
}

update_active_pane :: proc() {
    should_cursor_blink :: proc(p: ^Pane) -> bool {
        return p.cursor_blink_count < CURSOR_BLINK_MAX_COUNT &&
            time.tick_diff(p.cursor_blink_timer, time.tick_now()) > CURSOR_BLINK_TIMEOUT
    }
    profiling_start("active_pane")
    pane := active_pane

    if time.tick_diff(last_keystroke, time.tick_now()) < CURSOR_RESET_TIMEOUT {
        pane.cursor_showing = true
        pane.cursor_blink_count = 0
        pane.cursor_blink_timer = time.tick_now()
        flag_pane(pane, {.Need_Full_Repaint})
    }

    if should_cursor_blink(pane) {
        pane.cursor_showing = !pane.cursor_showing
        pane.cursor_blink_count += 1
        pane.cursor_blink_timer = time.tick_now()

        if pane.cursor_blink_count >= CURSOR_BLINK_MAX_COUNT {
            pane.cursor_showing = true
        }

        flag_pane(pane, {.Need_Full_Repaint})
    }

    for cursor in pane.cursors {
        if cursor.active {
            lines := get_lines_array(pane)
            coords := cursor_offset_to_coords(pane, lines, cursor.pos)
            has_scrolled := false

            for coords.column < pane.x_offset {
                pane.x_offset -= 1
                has_scrolled = true
            }

            for coords.column >= pane.visible_columns + pane.x_offset {
                pane.x_offset += 1
                has_scrolled = true
            }

            for coords.row < pane.y_offset {
                pane.y_offset -= 1
                has_scrolled = true
            }

            for coords.row >= pane.visible_rows + pane.y_offset {
                pane.y_offset += 1
                has_scrolled = true
            }

            if has_scrolled do flag_pane(pane, {.Need_Full_Repaint})
            break
        }
    }
    profiling_end()
}

update_and_draw_panes :: proc() {
    profiling_start("all panes: update and draw")
    for pane in open_panes {
        assert(pane.buffer != nil)
        assert(pane.texture != nil)

        if .Need_Full_Repaint not_in pane.flags {
            draw_texture(pane.texture, nil, &pane.rect)
            continue
        }

        set_target(pane.texture)
        set_color(.background)
        prepare_for_drawing()

        size_of_gutter := get_gutter_size(pane)
        initial_pen := Vector2{size_of_gutter, 0}
        if settings.modeline_position == .top do initial_pen.y = get_modeline_height()

        lines := get_lines_array(pane)
        first_row := pane.y_offset
        last_row := min(pane.y_offset + pane.visible_rows + 1, len(lines) - 1)
        first_offset, last_offset := lines[first_row], lines[last_row]
        code_lines := make([dynamic]Code_Line, context.temp_allocator)
        selections := make([dynamic]Range, 0, len(pane.cursors), context.temp_allocator)

        for cursor in pane.cursors {
            if !has_selection(cursor) do continue
            if (cursor.pos < first_offset || cursor.pos > last_offset) &&
                (cursor.sel < first_offset || cursor.sel > last_offset) {
                    continue
                }

            low, high := sorted_cursor(cursor)
            append(&selections, Range{start = low, end = high})
        }

        for line_number in first_row..<last_row {
            code_line := Code_Line{}
            start, _ := get_line_boundaries(line_number, lines)
            code_line.start_offset = start
            code_line.line = get_line_text(pane, line_number, lines)
            code_line.line_is_wrapped = false
            append(&code_lines, code_line)
        }

        draw_code(pane, pane.font, initial_pen, code_lines[:], selections[:])

        for cursor in pane.cursors {
            out_of_bounds, cursor_pen, rune_behind_cursor := prepare_cursor_for_drawing(pane, pane.font, initial_pen, cursor)
            _ = rune_behind_cursor

            if !out_of_bounds do draw_cursor(
                pane.font, cursor_pen, rune_behind_cursor, pane.cursor_showing, is_pane_focused(pane),
            )
        }

        draw_gutter(pane)
        draw_modeline(pane)

        // NOTE(nawe) after doing redraw, we can recalculate the
        // amount of columns visible thanks to knowing the gutter
        // size.
        pane.visible_columns = (int(pane.rect.w) - int(size_of_gutter)) / int(pane.font.xadvance) - 1

        set_target()
        draw_texture(pane.texture, nil, &pane.rect)
        unflag_pane(pane, {.Need_Full_Repaint})
    }
    profiling_end()
}

update_pane_font :: #force_inline proc(pane: ^Pane) {
    scaled_character_height := i32(f32(pane.local_font_size) * dpi_scale)
    pane.font = get_font_with_size(FONT_EDITOR_NAME, FONT_EDITOR_DATA, scaled_character_height)
}

update_all_pane_textures :: proc() {
    // NOTE(nawe) should be safe to clean up textures here since we're
    // probably recreating them due to the change in size
    pane_width := window_width / i32(len(open_panes))
    pane_height := window_height

    for &pane, index in open_panes {
        update_pane_font(pane)
        texture_destroy(pane.texture)

        pane.rect = make_rect(pane_width * i32(index), 0, pane_width, pane_height)
        pane.texture = texture_create(.TARGET, i32(pane_width), i32(pane_height))
        pane.visible_columns = int(pane.rect.w) / int(pane.font.xadvance) - 1
        pane.visible_rows = (int(pane.rect.h) / int(pane.font.line_height)) - 1
        if .Line_Wrappings in pane.modes do recalculate_line_wrappings(pane)
        flag_pane(pane, {.Need_Full_Repaint})
    }
}

recalculate_line_wrappings :: proc(pane: ^Pane) {
    unimplemented()
}

flag_pane :: #force_inline proc(pane: ^Pane, flags: Pane_Flags) {
    pane.flags += flags
}

unflag_pane :: #force_inline proc(pane: ^Pane, flags: Pane_Flags) {
    pane.flags -= flags
}

add_cursor :: proc(p: ^Pane, pos := 0) {
    append(&p.cursors, Cursor{
        active = true,
        pos = pos,
        sel = pos,
        last_column = -1,
    })
}

clone_cursor :: proc(p: ^Pane, cursor_to_clone: Cursor) -> ^Cursor {
    append(&p.cursors, cursor_to_clone)
    return &p.cursors[len(p.cursors) - 1]
}

prepare_cursor_for_drawing :: #force_inline proc(
    pane: ^Pane, font: ^Font, starting_pen: Vector2, cursor: Cursor,
) -> (out_of_screen: bool, pen: Vector2, rune_behind_cursor: rune) {
    lines := get_lines_array(pane)
    coords := cursor_offset_to_coords(pane, lines, cursor.pos)

    if !is_within_viewport(pane, coords) do return true, {}, ' '

    pen = starting_pen
    line_text := get_line_text_until_offset(pane, coords.row, lines, cursor.pos)

    pen.x += prepare_text(font, line_text) - i32(pane.x_offset) * font.xadvance
    pen.y += i32(coords.row - pane.y_offset) * font.character_height
    rune_behind_cursor = ' '

    if cursor.pos < len(pane.contents.buf) {
        rune_behind_cursor = utf8.rune_at(strings.to_string(pane.contents), cursor.pos)
    }

    return false, pen, rune_behind_cursor
}

is_within_viewport :: #force_inline proc(pane: ^Pane, coords: Coords) -> bool {
    last_column := pane.visible_columns + pane.x_offset
    last_row := pane.visible_rows + pane.y_offset
    return coords.column >= pane.x_offset && coords.column < last_column &&
        coords.row >= pane.y_offset && coords.row < last_row
}

cursor_offset_to_coords :: #force_inline proc(pane: ^Pane, lines: []int, offset: int) -> (result: Coords) {
    result.row = get_line_index(offset, lines)
    start, end := get_line_boundaries(result.row, lines)
    buf := pane.contents.buf[start:end]
    index := 0

    for index < offset - start {
        result.column += 1
        index += 1
        for index < len(buf) && is_continuation_byte(buf[index]) do index += 1
    }

    return
}

cursor_coords_to_offset :: #force_inline proc(pane: ^Pane, lines: []int, coords: Coords) -> (offset: int) {
    offset = lines[coords.row]
    column := coords.column
    for column > 0 {
        column -= 1
        offset += 1
        for is_continuation_byte(pane.contents.buf[offset]) do offset += 1
    }
    return
}

is_in_line :: #force_inline proc(offset: int, lines: []int, line_index: int) -> bool {
    start, end := get_line_boundaries(line_index, lines)
    return offset >= start && offset <= end
}

get_line_index :: #force_inline proc(offset: int, lines: []int) -> (line_index: int) {
    for _, index in lines {
        if is_in_line(offset, lines, index) do return index
    }
    return 0
}

get_line_text :: #force_inline proc(pane: ^Pane, line_index: int, lines: []int) -> (result: string) {
    result = strings.to_string(pane.contents)
    start, end := get_line_boundaries(line_index, lines)
    return result[start:end]
}

get_line_text_until_offset :: #force_inline proc(pane: ^Pane, line_index: int, lines: []int, offset: int) -> string {
    result := strings.to_string(pane.contents)
    start, _ := get_line_boundaries(line_index, lines)
    return result[start:offset]
}

get_line_boundaries :: #force_inline proc(line_index: int, lines: []int) -> (start, end: int) {
    next_line_index := min(line_index + 1, len(lines) - 1)
    start = lines[line_index]
    end = lines[next_line_index] - 1
    return
}

get_lines_array :: #force_inline proc(pane: ^Pane) -> []int {
    if .Line_Wrappings in pane.modes {
        return pane.wrapped_line_starts[:]
    } else {
        return pane.line_starts[:]
    }
}

has_selection :: #force_inline proc(cursor: Cursor) -> bool {
    return cursor.pos != cursor.sel
}

sorted_cursor :: #force_inline proc(cursor: Cursor) -> (low, high: int) {
    low  = min(cursor.pos, cursor.sel)
    high = max(cursor.pos, cursor.sel)
    return
}

is_pane_focused :: proc(pane: ^Pane) -> bool {
    return !global_widget.active && active_pane == pane
}

get_gutter_size :: proc(pane: ^Pane) -> (gutter_size: i32) {
    font := fonts_map[.UI_Small]
    gutter_size = font.em_width

    if settings.show_line_numbers {
        buffer_lines := pane.line_starts[:]
        size_test_str := fmt.tprintf("{}", len(buffer_lines))
        gutter_size = prepare_text(font, size_test_str) + MINIMUM_GUTTER_PADDING * font.em_width
    }

    return
}

get_modeline_height :: #force_inline proc() -> i32 {
    MODELINE_PADDING :: 8
    font := fonts_map[.UI_Regular]
    return font.line_height + MODELINE_PADDING
}

switch_to_buffer :: proc(pane: ^Pane, buffer: ^Buffer) {
    clear(&pane.cursors)
    add_cursor(pane)

    if len(buffer.cursors) > 0 {
        delete(pane.cursors)
        pane.cursors = slice.clone_to_dynamic(buffer.cursors)
    }

    pane.buffer = buffer
    flag_buffer(buffer, {.Dirty})
    flag_pane(pane, {.Need_Full_Repaint})
}

translate_position :: proc(pane: ^Pane, pos: int, t: Translation, max_column := -1) -> (result, last_column: int) {
    is_space :: proc(b: byte) -> bool {
        return b == ' ' || b == '\n' || b == '\t'
    }

    is_word_delim :: proc(b: byte) -> bool {
        return is_space(b) || b == '_'
    }

    buf := strings.to_string(pane.contents)
    result = clamp(pos, 0, len(buf))
    lines := get_lines_array(pane)

    switch t {
    case .start: result = 0
    case .end:   result = len(buf)

    case .down:
        coords := cursor_offset_to_coords(pane, lines, result)
        coords.row = min(coords.row + 1, len(lines))
        start, end := get_line_boundaries(coords.row, lines)
        column_length := end - start
        if coords.column == 0 do coords.column = max(0, max_column)
        coords.column = min(coords.column, column_length)
        result = cursor_coords_to_offset(pane, lines, coords)
    case .left:
        result -= 1
        for result >= 0 && is_continuation_byte(buf[result]) do result -= 1
    case .right:
        result += 1
        for result < len(buf) && is_continuation_byte(buf[result]) do result += 1
    case .up:
        coords := cursor_offset_to_coords(pane, lines, result)

        if coords.row > 0 {
            coords.row -= 1
            start, end := get_line_boundaries(coords.row, lines)
            column_length := end - start
            if coords.column == 0 do coords.column = max(0, max_column)
            coords.column = min(coords.column, column_length)
            result = cursor_coords_to_offset(pane, lines, coords)
        } else {
            result = 0
            last_column = -1
            return
        }
    case .prev_word:
        for result > 0 && is_word_delim(buf[result-1])  do result -= 1
        for result > 0 && !is_word_delim(buf[result-1]) do result -= 1
    case .next_word:
        for result < len(buf) && !is_word_delim(buf[result]) do result += 1
        for result < len(buf) && is_word_delim(buf[result])  do result += 1
    case .prev_paragraph:
        coords := cursor_offset_to_coords(pane, lines, result)
        coords.row = max(coords.row - 1, 0)
        start, end := get_line_boundaries(coords.row, lines)
        for coords.row > 0 && end - start > 1 {
            coords.row -= 1
            start, end = get_line_boundaries(coords.row, lines)
        }

        coords.column = 0
        last_column = -1
        result = cursor_coords_to_offset(pane, lines, coords)
    case .next_paragraph:
        coords := cursor_offset_to_coords(pane, lines, result)
        coords.row = min(coords.row + 1, len(lines))
        start, end := get_line_boundaries(coords.row, lines)
        for coords.row < len(lines) && end - start > 1 {
            coords.row += 1
            start, end = get_line_boundaries(coords.row, lines)
        }

        coords.column = 0
        last_column = -1
        result = cursor_coords_to_offset(pane, lines, coords)
    case .beginning_of_line:
        coords := cursor_offset_to_coords(pane, lines, result)

        if coords.column == 0 {
            for result < len(buf) && is_space(buf[result]) do result += 1
        } else {
            coords.column = 0
            result = cursor_coords_to_offset(pane, lines, coords)
        }

        last_column = -1
    case .end_of_line:
        coords := cursor_offset_to_coords(pane, lines, result)
        _, end := get_line_boundaries(coords.row, lines)
        last_column = -1
        result = end
    }

    result = clamp(result, 0, len(buf))
    if max_column != - 1 {
        result_coords := cursor_offset_to_coords(pane, lines, result)
        last_column = max(max_column, result_coords.column)
    }

    return
}
