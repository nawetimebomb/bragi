package main

import     "core:fmt"
import     "core:log"
import     "core:slice"
import     "core:strings"
import     "core:unicode/utf8"

import sdl "vendor:sdl3"

Rect    :: sdl.FRect
Surface :: sdl.Surface
Texture :: sdl.Texture
Vector2 :: distinct [2]i32

Coords :: struct {
    row, column: int,
}

Range :: struct {
    start, end: int,
}

texture_create :: #force_inline proc(access: sdl.TextureAccess, w, h: i32) -> ^Texture {
    return sdl.CreateTexture(renderer, .RGBA32, access, w, h)
}

texture_destroy :: #force_inline proc(texture: ^Texture) {
    sdl.DestroyTexture(texture)
}

make_rect :: #force_inline proc(x, y, w, h: i32) -> Rect {
    return Rect{f32(x), f32(y), f32(w), f32(h)}
}

prepare_for_drawing :: #force_inline proc() {
    sdl.RenderClear(renderer)
}

draw_frame :: #force_inline proc() {
    sdl.RenderPresent(renderer)
}

draw_texture :: #force_inline proc(texture: ^Texture, src, dest: ^Rect, loc := #caller_location) {
    if !sdl.RenderTexture(renderer, texture, src, dest) {
        log.errorf("failed to render texture at '{}'", loc)
    }
}

set_color :: proc{
    set_color_texture,
    set_color_background,
}

set_color_texture :: #force_inline proc(face: Face_Color, texture: ^Texture) {
    c := colorscheme[face]
    sdl.SetTextureColorMod(texture, c.r, c.g, c.b)
}

set_colors :: #force_inline proc(face: Face_Color, textures: []^Texture) {
    for t in textures do set_color_texture(face, t)
}

set_color_background :: #force_inline proc(face: Face_Color) {
    c := colorscheme[face]
    sdl.SetRenderDrawColor(renderer, c.r, c.g, c.b, c.a)
}

set_target :: #force_inline proc(target: ^Texture = nil) {
    sdl.SetRenderTarget(renderer, target)
}

draw_code :: proc(pane: ^Pane, font: ^Font, pen: Vector2, code_lines: []Code_Line, selections: []Range = {}) {
    is_selected :: proc(selections: []Range, offset: int) -> bool {
        for s in selections {
            if s.start != s.end && offset >= s.start && offset < s.end do return true
        }
        return false
    }

    for code, y_offset in code_lines {
        sx := pen.x - i32(pane.x_offset) * font.xadvance
        sy := pen.y + (i32(y_offset) * font.line_height)

        for r, x_offset in code.line {
            glyph := find_or_create_glyph(font, r)
            src := make_rect(glyph.x, glyph.y, glyph.w, glyph.h)
            dest := make_rect(sx, sy, glyph.w, glyph.h)

            if is_selected(selections, code.start_offset + x_offset) {
                set_color(.region)
                draw_rect(sx, sy, font.em_width, font.character_height, true)
            }

            set_color(.foreground, font.texture)
            draw_texture(font.texture, &src, &dest)
            sx += glyph.xadvance
        }

        if is_selected(selections, code.start_offset + len(code.line)) {
            set_color(.region)
            draw_rect(sx, sy, window_width - sx, font.line_height, true)
        }
    }
}

draw_cursor :: proc(font: ^Font, pen: Vector2, rune_behind: rune, visible: bool, filled: bool, active: bool) {
    cursor_height := font.character_height
    cursor_width := font.em_width if settings.cursor_is_a_block else i32(settings.cursor_width)

    if active {
        set_color(.cursor_active)
    } else {
        set_color(.cursor_inactive)
    }

    if filled {
        if visible || !active {
            draw_rect(pen.x, pen.y, cursor_width, cursor_height, true)

            if settings.cursor_is_a_block && (rune_behind != ' ' && rune_behind != '\n') {
                glyph := find_or_create_glyph(font, rune_behind)
                src := make_rect(glyph.x, glyph.y, glyph.w, glyph.h)
                dest := make_rect(pen.x, pen.y, glyph.w, glyph.h)
                set_color(.background, font.texture)
                draw_texture(font.texture, &src, &dest)
            }
        }
    } else {
        draw_rect(pen.x, pen.y, cursor_width, cursor_height, false)
    }
}

draw_gutter :: proc(pane: ^Pane) {
    draw_gutter_extension :: proc(pane: ^Pane, font: ^Font, pen: Vector2, line_number: int, lines: []int) {
        left_indicator, right_indicator := get_gutter_indicators(font)
        start, end := get_line_boundaries(line_number, lines)
        text := string(pane.contents.buf[start:end])
        count := utf8.rune_count_in_string(text)

        set_color(.ui_line_number_foreground_current, font.texture)
        if pane.x_offset > 0 {
            draw_text(font, pen, left_indicator)
        }
        if count > pane.visible_columns + pane.x_offset {
            draw_text(font, {i32(pane.rect.w) - font.em_width, pen.y}, right_indicator)
        }
    }

    pane_height := i32(pane.rect.h)
    font := fonts_map[.UI_Small]
    regular_character_height := pane.font.line_height
    line_number_character_height := font.line_height
    y_offset_for_centering := (regular_character_height - line_number_character_height)/2
    buffer_lines := pane.line_starts[:]
    first_visible_row := pane.y_offset
    last_visible_row := pane.y_offset + pane.visible_rows
    last_line := len(buffer_lines) - 1
    gutter_size := get_gutter_size(pane)
    pen := Vector2{}

    if settings.modeline_position == .top {
        pen.y = get_modeline_height()
    }

    if settings.show_line_numbers {
        size_test_str := fmt.tprintf("{}", len(buffer_lines))
        set_color(.ui_line_number_background)
        draw_rect(0, 0, gutter_size, pane_height, true)
        draw_rect(i32(pane.rect.w) - font.em_width, 0, font.em_width, pane_height, true)

        current_rows := make([dynamic]int, context.temp_allocator)
        for cursor in pane.cursors do append(&current_rows, get_line_index(cursor.pos, buffer_lines))

        for line_number in first_visible_row..<last_visible_row {
            if line_number >= last_line do break

            if slice.contains(current_rows[:], line_number) {
                set_color(.ui_line_number_background_current)
                draw_rect(0, pen.y, gutter_size, regular_character_height)
                set_color(.ui_line_number_foreground_current, font.texture)
            } else {
                set_color(.ui_line_number_foreground, font.texture)
            }

            pen.y += y_offset_for_centering
            line_number_str := strings.right_justify(
                fmt.tprintf("{}", line_number + 1),
                len(size_test_str) + GUTTER_LINE_NUMBER_JUSTIFY,
                " ", context.temp_allocator,
            )
            draw_text(font, pen, line_number_str)
            draw_gutter_extension(pane, font, pen, line_number, buffer_lines)
            pen.y += regular_character_height - y_offset_for_centering
        }

    } else {
        set_color(.ui_line_number_background)
        draw_rect(0, 0, gutter_size, pane_height, true)
        draw_rect(i32(pane.rect.w) - gutter_size, 0, gutter_size, pane_height, true)

        for line_number in first_visible_row..<last_visible_row {
            if line_number >= last_line do break

            pen.y += y_offset_for_centering
            draw_gutter_extension(pane, font, pen, line_number, buffer_lines)
            pen.y += regular_character_height - y_offset_for_centering
        }
    }

    if pane.rect.x > 0 {
        set_color(.ui_border)
        draw_line(0, 0, 0, pane_height)
    }

    return
}

draw_modeline :: proc(pane: ^Pane) {
    is_focused := is_pane_focused(pane)

    font := fonts_map[.UI_Regular]
    font_bold := fonts_map[.UI_Bold]
    font_italic := fonts_map[.UI_Italic]

    modeline_background: Face_Color = is_focused ? .ui_modeline_active_background : .ui_modeline_inactive_background
    modeline_foreground: Face_Color = is_focused ? .ui_modeline_active_foreground : .ui_modeline_inactive_foreground
    modeline_highlight:  Face_Color = is_focused ? .ui_modeline_active_highlight  : .ui_modeline_inactive_highlight

    modeline_height := get_modeline_height()
    modeline_width := i32(pane.rect.w)
    modeline_y_pos: i32 = 0

    if settings.modeline_position == .bottom {
        modeline_y_pos = i32(pane.rect.h) - modeline_height
        if global_widget.active do modeline_y_pos -= i32(global_widget.rect.h)
    }

    y_offset_for_centering := (modeline_height - font.line_height)/2

    left_pen := Vector2{0, modeline_y_pos  + y_offset_for_centering}
    right_pen := Vector2{i32(pane.rect.w), left_pen.y}
    modified := is_modified(pane.buffer)

    set_color(modeline_background)
    draw_rect(0, modeline_y_pos, modeline_width, modeline_height)

    if modified {
        set_colors(modeline_highlight, {font.texture, font_bold.texture})
    } else {
        set_colors(modeline_foreground, {font.texture, font_bold.texture})
    }

    status_str := fmt.tprintf(
        " {} ",
        modified ? "+" : "-",
    )
    left_pen = draw_text(font, left_pen, status_str)
    left_pen = draw_text(font_bold, left_pen, pane.buffer.name)

    if is_crlf(pane.buffer) {
        set_color(modeline_highlight, font_italic.texture)
        left_pen = draw_text(font_italic, left_pen, " [CRLF replaced with LF] ")
    }

    set_color(modeline_foreground, font.texture)
    if len(pane.cursors) == 1 {
        // using the buffer lines for these coords, we want to know the real position of the cursor
        coords := cursor_offset_to_coords(pane, pane.line_starts[:], pane.cursors[0].pos)
        left_pen = draw_text(font, left_pen, fmt.tprintf(" ({}, {}) ", coords.row + 1, coords.column))
    } else {
        // TODO(nawe) maybe show the position of the active cursor
        left_pen = draw_text(font, left_pen, fmt.tprintf(" ({} cursors)", len(pane.cursors)))
    }

    // only show this side if there's space for it. Hopefully this is sufficient.
    if pane.rect.w > MINIMUM_WINDOW_SIZE * 0.8 {
        set_color(modeline_foreground, font_bold.texture)
        major_mode_name := get_major_mode_name(pane.buffer)
        major_mode_width := prepare_text(font_bold, major_mode_name)
        right_pen.x -= major_mode_width + font_bold.em_width
        draw_text(font_bold, right_pen, major_mode_name)
    }
}

draw_rect :: #force_inline proc(x, y, w, h: i32, fill := true) {
    rect := make_rect(x, y, w, h)

    if fill {
        sdl.RenderFillRect(renderer, &rect)
    } else {
        sdl.RenderRect(renderer, &rect)
    }
}

draw_line :: #force_inline proc(x1, y1, x2, y2: i32) {
    sdl.RenderLine(renderer, f32(x1), f32(y1), f32(x2), f32(y2))
}

draw_highlighted_text :: proc(
    regular_font: ^Font, highlight_font: ^Font,
    regular_face, highlight_bg_face, highlight_fg_face: Face_Color,
    pen: Vector2, text: string, highlights: []Range, selected := false,
) -> (pen2: Vector2) {
    sx, sy := pen.x, pen.y

    is_highlighted :: proc(highlights: []Range, offset: int) -> bool {
        for h in highlights {
            if h.start == h.end do continue
            if offset >= h.start && offset < h.end do return true
        }
        return false
    }

    for r, offset in text {
        highlighted := is_highlighted(highlights, offset)
        face := selected ? highlight_fg_face : regular_face
        font := highlighted ? highlight_font : regular_font

        if r == '\t' {
            // TODO(nawe) add tab width
            sx += 4 * font.xadvance
            continue
        }

        if r == '\n' {
            sx = pen.x
            sy += font.line_height
            continue
        }

        set_color(face, font.texture)
        glyph := find_or_create_glyph(font, r)

        if highlighted && !selected {
            set_color(highlight_bg_face)
            draw_rect(sx, sy, glyph.w, glyph.h)
            set_color(highlight_fg_face, font.texture)
        }

        src := make_rect(glyph.x, glyph.y, glyph.w, glyph.h)
        dest := make_rect(sx, sy, glyph.w, glyph.h)
        draw_texture(font.texture, &src, &dest)
        sx += glyph.xadvance
    }

    return {sx, sy}
}

draw_text :: proc(font: ^Font, pen: Vector2, text: string) -> (pen2: Vector2) {
    sx, sy := pen.x, pen.y

    for r in text {
        if r == '\t' {
            sx += 4 * font.xadvance
            continue
        }

        if r == '\n' {
            sx = pen.x
            sy += font.line_height
            continue
        }

        glyph := find_or_create_glyph(font, r)
        src := make_rect(glyph.x, glyph.y, glyph.w, glyph.h)
        dest := make_rect(sx, sy, glyph.w, glyph.h)
        draw_texture(font.texture, &src, &dest)
        sx += glyph.xadvance
    }

    return {sx, sy}
}
