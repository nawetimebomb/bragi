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
    line: string,
    tokens: []tokenizer.Token_Kind,
}

Cursor_Settings :: struct {
    fill: bool,
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

render_pane :: proc(p: ^Pane, index: int, focused: bool) {
    profiling_start("render.odin:render_pane")
    colors := &bragi.settings.colorscheme_table
    viewport := p.viewport
    buffer := p.buffer

    set_renderer_target(p.texture)

    clear_background(colors[.background])

    if index > 0 {
        set_bg(colors[.ui_border])
        draw_line(0, 0, 0, p.rect.h)
    }

    { // Start Buffer
        mm := buffer.major_mode
        screen_buffer := buffer.str
        cursor_settings := Cursor_Settings{
            fill = focused,
            showing = p.cursor_showing,
        }
        first_line := int(p.viewport.y)
        last_line :=
            min(int(p.viewport.y + p.relative_size.y + 2), len(buffer.lines) - 1)

        if len(buffer.lines) > int(p.relative_size.y) {
            start := buffer.lines[first_line][0]
            end := buffer.lines[last_line][1]
            screen_buffer = buffer.str[start:end]
        }

        if mm == .Fundamental {
            draw_text(font_editor, screen_buffer, p.cursors[:], cursor_settings)
        } else {
            code_lines := make([]Code_Line, last_line - first_line, context.temp_allocator)

            for li in first_line..<last_line {
                index := li - first_line
                code_line := Code_Line{}
                start, end := get_line_boundaries(buffer, li)
                code_line.line = buffer.str[start:end]
                code_line.tokens = buffer.tokens[start:end]
                code_lines[index] = code_line
            }

            draw_code(font_editor, code_lines[:], p.cursors[:], cursor_settings)
        }
    } // End Buffer

    { // Start Modeline
        HORIZONTAL_PADDING :: 10
        VERTICAL_PADDING   :: 3
        cursor_head, _ := get_last_cursor(p)
        line_number := cursor_head.y + 1
        buffer_status := get_buffer_status(buffer)
        buffer_name_indices := [2]int{
            len(buffer_status), len(buffer_status) + len(buffer.name),
        }

        lml_fmt := fmt.tprintf(
            "{0} {1} ({2}, {3})",
            get_buffer_status(buffer),
            buffer.name,
            line_number,
            cursor_head.x,
        )
        rml_fmt := fmt.tprintf(
            "{0}", settings_get_major_mode_name(buffer.major_mode),
        )
        rml_fmt_size := i32(len(rml_fmt)) * font_ui.em_width
        row := p.rect.h - font_ui.line_height - VERTICAL_PADDING
        background_y := row - VERTICAL_PADDING
        borderline_y := background_y - 1
        background_h := font_ui.line_height + VERTICAL_PADDING * 2

        left_start_column  :: HORIZONTAL_PADDING
        right_start_column := p.rect.w - HORIZONTAL_PADDING - rml_fmt_size

        set_bg(colors[.ui_border])
        draw_line(0, borderline_y, p.rect.w, borderline_y)

        // TODO: This is adding a shadow to limit the modeline, it looks great, but I
        // rather create a texture with this and use it instead of doing it manually.
        // sdl.SetRenderDrawBlendMode(renderer, .BLEND)
        // for i : i32 = 0; i < 5; i += 1 {
        //     shadow := colors[.modeline_shadow]
        //     sdl.SetRenderDrawColor(renderer, shadow.r, shadow.g, shadow.b, shadow.a - 51 * u8(i))
        //     sdl.RenderDrawLine(
        //         renderer,
        //         0, background_y - i,
        //         p.rect.w, background_y - i,
        //     )
        // }
        // sdl.SetRenderDrawBlendMode(renderer, .NONE)

        background_rect := make_rect(0, background_y, p.rect.w, background_h)
        set_bg(focused ? colors[.modeline_on_bg] : colors[.modeline_off_bg])
        sdl.RenderFillRect(renderer, &background_rect)

        { // Left side
            x := i32(left_start_column)

            for r, index in lml_fmt {
                used_font := font_ui

                if buffer_name_indices[0] <= index && buffer_name_indices[1] >= index {
                    used_font = font_ui_bold
                }

                glyph := used_font.glyphs[r]
                src := make_rect(glyph.x, glyph.y, glyph.w, glyph.h)
                dest := make_rect(
                    f32(x + glyph.xoffset),
                    f32(row + glyph.yoffset) - used_font.y_offset_for_centering,
                    f32(glyph.w), f32(glyph.h),
                )
                set_fg(
                    used_font.texture,
                    focused ? colors[.modeline_on_fg] : colors[.modeline_off_fg],
                )
                draw_copy(used_font.texture, &src, &dest)
                x += glyph.xadvance
            }
        }

        { // Right side
            x := i32(right_start_column)

            for r, index in rml_fmt {
                glyph := font_ui.glyphs[r]
                src := make_rect(glyph.x, glyph.y, glyph.w, glyph.h)
                dest := make_rect(
                    f32(x + glyph.xoffset),
                    f32(row + glyph.yoffset) - font_ui.y_offset_for_centering,
                    f32(glyph.w), f32(glyph.h),
                )
                set_fg(
                    font_ui.texture,
                    focused ? colors[.modeline_on_fg] : colors[.modeline_off_fg],
                )
                draw_copy(font_ui.texture, &src, &dest)
                x += font_ui.em_width
            }
        }
    } // End Modeline

    set_renderer_target()

    sdl.RenderCopy(renderer, p.texture, nil, &p.rect)
    profiling_end()
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

draw_text :: proc(
    font: Font,
    string_buffer: string,
    selections: []Cursor,
    cursor_settings: Cursor_Settings,
) {
    colors := bragi.settings.colorscheme_table
    sx, sy: i32

    set_fg(font.texture, colors[.default])

    for r in string_buffer {
        if r == '\n' {
            sx = 0
            sy += font.line_height
            continue
        }

        g := font.glyphs[r]

        if !is_valid_glyph(r) {
            g = font.glyphs['?']
        }

        src := sdl.Rect{ g.x, g.y, g.w, g.h }
        dest := sdl.FRect{
            f32(sx + g.xoffset),
            f32(sy + g.yoffset) - y_offset_for_centering,
            f32(g.w), f32(g.h),
        }
        draw_copy(font.texture, &src, &dest)
        sx += g.xadvance
    }
}

draw_code :: proc(
    font: Font,
    code_lines: []Code_Line,
    selections: []Cursor,
    cursor_settings: Cursor_Settings,
) {
    colors := bragi.settings.colorscheme_table
    line_height := font.line_height

    for code, y_offset in code_lines {
        sx, sy: i32
        sy = auto_cast y_offset * line_height

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

            switch code.tokens[x_offset] {
            case .generic:      set_fg(font.texture, colors[.default])
            case .builtin:      set_fg(font.texture, colors[.builtin])
            case .comment:      set_fg(font.texture, colors[.comment])
            case .constant:     set_fg(font.texture, colors[.constant])
            case .keyword:      set_fg(font.texture, colors[.keyword])
            case .preprocessor: set_fg(font.texture, colors[.preprocessor])
            case .string:       set_fg(font.texture, colors[.string])
            case .type:         set_fg(font.texture, colors[.type])
            }

            draw_copy(font.texture, &src, &dest)
            sx += g.xadvance
        }
    }

    for cursor in selections {
        // Cursor tail
        if cursor.tail != cursor.head {
            // TODO: add Cursor tail
        }

        // NOTE: We skip the cursor head rendering if it's not showing
        if !cursor_settings.showing { continue }

        // Cursor head
        ch := cursor.head
        cursor_rect := make_rect(
            0, i32(ch.y) * font.line_height,
            font.em_width, font.line_height,
        )
        char_behind_cursor: byte

        if ch.y < len(code_lines) {
            str := code_lines[ch.y].line
            cut := clamp(ch.x, 0, len(str))
            cursor_rect.x = get_width_based_on_text_size(font, str[:cut], ch.x)
            if ch.x < len(str) - 1 {
                char_behind_cursor = code_lines[ch.y].line[ch.x]
            }
        }

        draw_cursor(
            font, cursor_rect, cursor_settings.fill, char_behind_cursor,
        )
    }
}

draw_cursor :: #force_inline proc(f: Font, r: Rect, fill: bool, behind_cursor: byte) {
    colors := bragi.settings.colorscheme_table
    set_bg(colors[.cursor])
    draw_rect(r.x, r.y, r.w, r.h, fill)

    if is_valid_glyph(rune(behind_cursor)) {
        g := f.glyphs[behind_cursor]
        src := make_rect(g.x, g.y, g.w, g.h)
        dest := make_rect(
            f32(r.x + g.xoffset),
            f32(r.y + g.yoffset) - f.y_offset_for_centering,
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
