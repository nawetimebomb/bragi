package main

import     "core:fmt"
import     "core:slice"
import     "core:strings"
import     "core:time"
import     "tokenizer"
import sdl "vendor:sdl2"

Rect :: sdl.Rect
Texture :: ^sdl.Texture

Code_Line :: struct {
    line:         string,
    start_offset: int,
    tokens:       []tokenizer.Token_Kind,
}

Cursor_Settings :: struct {
    fill:    bool,
    showing: bool,
}

set_bg :: #force_inline proc(c: Color) {
    if c.a != 0 {
        sdl.SetRenderDrawColor(renderer, c.r, c.g, c.b, c.a)
    }
}

set_fg :: #force_inline proc(t: ^sdl.Texture, c: Color) {
    if c.a != 0 {
        sdl.SetTextureColorMod(t, c.r, c.g, c.b)
    }
}

set_fg_for_token :: #force_inline proc(t: ^sdl.Texture, k: tokenizer.Token_Kind) {
    colors := bragi.settings.colorscheme_table

    switch k {
    case .generic:      set_fg(t, colors[.default])
    case .builtin:      set_fg(t, colors[.builtin])
    case .comment:      set_fg(t, colors[.comment])
    case .constant:     set_fg(t, colors[.constant])
    case .keyword:      set_fg(t, colors[.keyword])
    case .preprocessor: set_fg(t, colors[.preprocessor])
    case .string:       set_fg(t, colors[.string])
    case .type:         set_fg(t, colors[.type])
    }
}

draw_modeline :: proc(p: ^Pane, focused: bool) {
    SMALL_PADDING :: 4
    MODELINE_H_PADDING :: 10
    MODELINE_V_PADDING :: 3
    colors := bragi.settings.colorscheme_table

    modeline_y := p.rect.h - font_ui.line_height - MODELINE_V_PADDING
    background_y := modeline_y - MODELINE_V_PADDING
    borderline_y := background_y - 1
    background_h := font_ui.line_height + MODELINE_V_PADDING * 2

    set_bg(colors[.ui_border])
    draw_line(0, borderline_y, p.rect.w, borderline_y)

    set_bg(focused ? colors[.modeline_on_bg] : colors[.modeline_off_bg])
    draw_rect(0, background_y, p.rect.w, background_h, true)

    // Left side
    {
        coords: Coords

        if focused {
            coords = get_last_cursor_pos_as_coords(p.buffer)
        } else {
            coords = get_coords(p.buffer, p.last_cursor_pos)
        }

        left_start_column  :: MODELINE_H_PADDING

        sx := draw_text(
            font_ui, get_buffer_status(p.buffer),
            p.buffer.modified ? .highlight : .default,
            left_start_column, modeline_y,
        )
        sx = draw_text(
            font_ui_bold, p.buffer.name,
            p.buffer.modified ? .highlight : .default,
            sx + font_ui.em_width, modeline_y,
        )

        line_number_column := fmt.tprintf(
            "({0}, {1})", coords.line + 1, coords.column,
        )
        draw_text(
            font_ui, line_number_column, .default,
            sx + font_ui.em_width * SMALL_PADDING, modeline_y,
        )
    }

    // Right side
    {
        major_mode_string := settings_get_major_mode_name(p.buffer.major_mode)
        content_size := get_text_size(font_ui, fmt.tprintf("{0}", major_mode_string))
        right_start_column := p.rect.w - MODELINE_H_PADDING - content_size

        draw_text(
            font_ui_bold, major_mode_string, .default,
            right_start_column, modeline_y,
        )
    }
}

make_rect :: proc{
    make_rect_f32,
    make_rect_i32,
    make_rect_i32_empty,
    make_rect_int,
}

make_rect_i32_empty :: #force_inline proc() -> sdl.Rect {
    return sdl.Rect{}
}

make_rect_int :: #force_inline proc(x, y, w, h: int) -> sdl.Rect {
    return make_rect_i32(i32(x), i32(y), i32(w), i32(h))
}

make_rect_i32 :: #force_inline proc(x, y, w, h: i32) -> sdl.Rect {
    return sdl.Rect{ x, y, w, h }
}

make_rect_f32 :: #force_inline proc(x, y, w, h: f32) -> sdl.FRect {
    return sdl.FRect{ x, y, w, h }
}

make_texture :: #force_inline proc(
    handle: ^sdl.Texture,
    format: sdl.PixelFormatEnum,
    access: sdl.TextureAccess,
    rect: sdl.Rect,
) -> Texture {
    sdl.DestroyTexture(handle)
    return sdl.CreateTexture(renderer, format, access, rect.w, rect.h)
}

is_valid_glyph :: proc(r: rune) -> bool {
    return r >= 32 && r < 128
}

clear_background :: #force_inline proc(color: Color) {
    set_bg(color)
    sdl.RenderClear(renderer)
}

draw_pane_divider :: proc() {
    colors := bragi.settings.colorscheme_table
    set_bg(colors[.ui_border])
    draw_line(0, 0, 0, window_height)
}

draw_gutter_line_numbers :: proc(
    prect: Rect,
    start, end, current: int,
) -> (gutter_size: i32) {
    GUTTER_PADDING :: 2
    LINE_NUMBER_JUSTIFY :: GUTTER_PADDING / 2
    colors := bragi.settings.colorscheme_table

    // Testing the size of the string by using the largest number, hopefully
    size_test_str := fmt.tprintf("{0}", end)
    gutter_size = get_width_based_on_text_size(
        font_ui, size_test_str, len(size_test_str) + GUTTER_PADDING,
    )

    set_bg(colors[.ui_gutter])
    draw_rect(0, 0, gutter_size, prect.h)
    set_bg(colors[.ui_border])
    draw_line(gutter_size, 0, gutter_size, prect.h)

    for line_number in start..<end {
        index := line_number - start
        sy := i32(line_number - start) * line_height
        line_number_str := strings.right_justify(
            fmt.tprintf("{0}", line_number + 1),
            len(size_test_str) + LINE_NUMBER_JUSTIFY,
            " ",
            context.temp_allocator,
        )
        draw_text(
            font_ui, line_number_str,
            current == index ? .ui_line_number_current : .ui_line_number,
            0, sy,
        )
    }

    return
}

draw_text :: proc(f: Font, s: string, color: Face, x, y: i32) -> (sx: i32) {
    colors := bragi.settings.colorscheme_table
    sx = x
    sy := y

    for r in s {
        g := f.glyphs[r]
        src := make_rect(g.x, g.y, g.w, g.h)
        dest := make_rect(
            f32(sx + g.xoffset),
            f32(sy + g.yoffset) - f.y_offset_for_centering,
            f32(g.w), f32(g.h),
        )

        set_fg(f.texture, colors[color])
        draw_copy(f.texture, &src, &dest)
        sx += g.xadvance
    }

    return sx
}

draw_code :: proc(
    font: Font,
    pen: [2]i32,
    code_lines: []Code_Line,
    selections: []Range = {},
    is_colored: bool,
) {
    colors := bragi.settings.colorscheme_table
    line_height := font.line_height

    is_selected :: proc(selections: []Range, offset: int) -> bool {
        for sel in selections {
            if offset >= sel.start && offset < sel.end { return true }
        }

        return false
    }

    for code, y_offset in code_lines {
        sx, sy: i32
        sx = pen.x
        sy = i32(y_offset) * line_height

        for r, x_offset in code.line {
            g := font.glyphs[r]

            if !is_valid_glyph(r) {
                g = font.glyphs['?']
            }

            src := make_rect(g.x, g.y, g.w, g.h)
            dest := make_rect(
                f32(sx + g.xoffset),
                f32(sy + g.yoffset) - font.y_offset_for_centering,
                f32(g.w), f32(g.h),
            )

            if is_colored {
                set_fg_for_token(font.texture, code.tokens[x_offset])
            } else {
                set_fg(font.texture, colors[.default])
            }

            if is_selected(selections, code.start_offset + x_offset) {
                set_bg(colors[.region])
                draw_rect(sx, sy, char_width, line_height, true)
            }

            draw_copy(font.texture, &src, &dest)
            sx += g.xadvance
        }
    }
}

draw_cursor :: #force_inline proc(
    f: Font,
    pen: [2]i32,
    r: Rect,
    fill: bool,
    behind_cursor: byte,
) {
    colors := bragi.settings.colorscheme_table
    set_bg(colors[.cursor])
    draw_rect(pen.x + r.x, pen.y + r.y, r.w, r.h, fill)

    if is_valid_glyph(rune(behind_cursor)) {
        g := f.glyphs[behind_cursor]
        src := make_rect(g.x, g.y, g.w, g.h)
        dest := make_rect(
            f32(pen.x + r.x + g.xoffset),
            f32(pen.y + r.y + g.yoffset) - f.y_offset_for_centering,
            f32(g.w), f32(g.h),
        )
        set_fg(f.texture, colors[.background])
        draw_copy(f.texture, &src, &dest)
    }
}

draw_line :: #force_inline proc(x1, y1, x2, y2: i32) {
    sdl.RenderDrawLine(renderer, x1, y1, x2, y2)
}

draw_rect :: #force_inline proc(x, y, w, h: i32, fill: bool = true) {
    rect := make_rect(x, y, w, h)
    if fill {
        sdl.RenderFillRect(renderer, &rect)
    } else {
        sdl.RenderDrawRect(renderer, &rect)
    }
}

draw_copy :: proc{
    draw_copy_frect,
    draw_copy_rect,
}

draw_copy_frect :: #force_inline proc(texture: ^sdl.Texture, src: ^sdl.Rect, dest: ^sdl.FRect) {
    sdl.RenderCopyF(renderer, texture, src, dest)
}

draw_copy_rect :: #force_inline proc(texture: ^sdl.Texture, src, dest: ^sdl.Rect) {
    sdl.RenderCopy(renderer, texture, src, dest)
}

set_renderer_target :: #force_inline proc(texture: ^sdl.Texture = nil) {
    sdl.SetRenderTarget(renderer, texture)
}
