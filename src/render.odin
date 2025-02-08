package main

import     "core:fmt"
import     "core:slice"
import     "core:strings"
import     "core:time"
import sdl "vendor:sdl2"
import "tokenizer"

Rect :: sdl.Rect
Texture :: ^sdl.Texture

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

    background      := colors[.background]
    builtin         := colors[.builtin]
    comment         := colors[.comment]
    constant        := colors[.constant]
    cursor          := colors[.cursor]
    default         := colors[.default]
    highlight       := colors[.highlight]
    keyword         := colors[.keyword]
    modeline_off_bg := colors[.modeline_off_bg]
    modeline_off_fg := colors[.modeline_off_fg]
    modeline_on_bg  := colors[.modeline_on_bg]
    modeline_on_fg  := colors[.modeline_on_fg]
    region          := colors[.region]
    string          := colors[.string]

    renderer_target(p.texture)

    set_bg(background)
    sdl.RenderClear(renderer)

    if index > 0 {
        set_bg(colors[.ui_border])
        draw_line(0, 0, 0, p.rect.h)
    }

    { // Start Buffer
        mm := buffer.major_mode
        screen_buffer := buffer.str
        first_line := int(p.viewport.y)
        last_line :=
            min(int(p.viewport.y + p.relative_size.y + 2), len(buffer.lines) - 1)

        if len(buffer.lines) > int(p.relative_size.y) {
            start := buffer.lines[first_line][0]
            end := buffer.lines[last_line][1]
            screen_buffer = buffer.str[start:end]
        }

        if mm == .Fundamental {
            draw_text(font_editor, screen_buffer)
        } else {
            visible_lines := make(
                []Code_Line,
                last_line - first_line,
                context.temp_allocator,
            )

            for li in first_line..<last_line {
                index := li - first_line
                code_line := Code_Line{}
                start, end := get_line_boundaries(buffer, li)
                code_line.line = buffer.str[start:end]
                code_line.tokens = buffer.tokens[start:end]
                visible_lines[index] = code_line
            }

            draw_code(font_editor, char_width, line_height, visible_lines[:])
        }
    } // End Buffer

    { // Start Cursor
        set_bg(cursor)
        pos, _ := get_last_cursor(p)
        x: f32
        y := f32(i32(pos.y) - viewport.y) * f32(line_height)
        start, end := get_line_boundaries(buffer, pos.y)
        rune_behind_cursor: rune

        for r, index in buffer.str[start:end] {
            if pos.x == index {
                rune_behind_cursor = r
                break
            }

            glyph := font_editor.glyphs[r]
            x += f32(glyph.xadvance)
        }

        dest := make_rect(x, y, f32(char_width), f32(line_height))

        set_bg(cursor)

        if focused && !widgets_pane.enabled {
            if !p.cursor_blinking {
                sdl.RenderFillRectF(renderer, &dest)

                // draw the glyph behind the cursor
                if rune_behind_cursor >= 32 && rune_behind_cursor < 128 {
                    glyph := font_editor.glyphs[rune_behind_cursor]
                    glyph_src := make_rect(glyph.x, glyph.y, glyph.w, glyph.h)
                    glyph_dest := make_rect(
                        x + f32(glyph.xoffset),
                        y + f32(glyph.yoffset) - y_offset_for_centering,
                        f32(glyph.w), f32(glyph.h),
                    )

                    set_fg(font_editor.texture, background)
                    draw_copy(font_editor.texture, &glyph_src, &glyph_dest)
                }
            }
        } else {
            sdl.RenderDrawRectF(renderer, &dest)
        }
    } // End Cursor

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
        set_bg(focused ? modeline_on_bg : modeline_off_bg)
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
                set_fg(used_font.texture, focused ? modeline_on_fg : modeline_off_fg)
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
                set_fg(font_ui.texture, focused ? modeline_on_fg : modeline_off_fg)
                draw_copy(font_ui.texture, &src, &dest)
                x += font_ui.em_width
            }
        }
    } // End Modeline

    renderer_target()

    sdl.RenderCopy(renderer, p.texture, nil, &p.rect)
    profiling_end()
}

make_rect :: proc{
    make_rect_f32,
    make_rect_i32,
    make_rect_i32_empty,
}

make_rect_i32_empty :: #force_inline proc() -> sdl.Rect {
    return sdl.Rect{}
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

draw_text :: proc(font: Font, string_buffer: string) {
    colors := bragi.settings.colorscheme_table
    sx, sy: i32

    is_valid_glyph :: proc(r: rune) -> bool {
        return r >= 32 && r < 128
    }

    set_fg(font.texture, colors[.default])

    for r in string_buffer {
        if r == '\n' {
            sx = 0
            sy += font.line_height
            continue
        }

        glyph := font.glyphs[r]

        if !is_valid_glyph(r) {
            glyph = font.glyphs['?']
        }

        src := sdl.Rect{ glyph.x, glyph.y, glyph.w, glyph.h }
        dest := sdl.FRect{
            f32(sx + glyph.xoffset),
            f32(sy + glyph.yoffset) - y_offset_for_centering,
            f32(glyph.w), f32(glyph.h),
        }
        draw_copy(font.texture, &src, &dest)
        sx += glyph.xadvance
    }
}

Code_Line :: struct {
    line: string,
    tokens: []tokenizer.Token_Kind,
}

draw_code :: proc(font: Font, char_xadvance: i32, line_height: i32, code_lines: []Code_Line) {
    colors := bragi.settings.colorscheme_table

    is_valid_glyph :: proc(r: rune) -> bool {
        return r >= 32 && r < 128
    }

    for code, y_offset in code_lines {
        sy := i32(y_offset) * line_height

        for r, x_offset in code.line {
            sx := i32(x_offset) * char_xadvance
            glyph := font.glyphs[r]

            if !is_valid_glyph(r) {
                glyph = font.glyphs['?']
            }

            src := sdl.Rect{ glyph.x, glyph.y, glyph.w, glyph.h }
            dest := sdl.FRect{
                f32(sx + glyph.xoffset),
                f32(sy + glyph.yoffset) - y_offset_for_centering,
                f32(glyph.w), f32(glyph.h),
            }

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
        }
    }

}

clear_background :: #force_inline proc(color: Color) {
    set_bg(color)
    sdl.RenderClear(renderer)
}

draw_line :: #force_inline proc(x1, y1, x2, y2: i32) {
    sdl.RenderDrawLine(renderer, x1, y1, x2, y2)
}

draw_fill_rect :: #force_inline proc(x, y, w, h: i32) {
    rect := make_rect(x, y, w, h)
    sdl.RenderFillRect(renderer, &rect)
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

renderer_target :: #force_inline proc(texture: ^sdl.Texture = nil) {
    sdl.SetRenderTarget(renderer, texture)
}
