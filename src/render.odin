package main

import     "core:fmt"
import     "core:strings"
import sdl "vendor:sdl2"
import     "languages"

is_caret_showing :: #force_inline proc(c: ^Caret, x, y, offset: i32) -> bool {
    return !c.blinking && i32(c.coords.x) == x && i32(c.coords.y) - offset == y
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
    pane_dest := sdl.Rect{ p.real_size.x * i32(index), 0, p.real_size.x, p.real_size.y }
    viewport := p.viewport
    caret := p.caret
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

    sdl.SetRenderTarget(renderer, bragi.ctx.pane_texture)

    set_bg(background)
    sdl.RenderClear(renderer)

    if index > 0 {
        set_bg(comment)
        sdl.RenderDrawLine(renderer, 0, 0, 0, window_height)
    }

    { // Start Buffer
        mm := buffer.major_mode
        lexer := languages.Lexer{}
        lexer_enabled := settings_is_lexer_enabled(mm)
        lex := settings_get_lexer_proc(mm)
        sx, sy: i32
        screen_buffer := buffer.str

        if len(buffer.lines) > int(p.relative_size.y) {
            culling_start := max(p.viewport.y, 0)
            culling_end :=
                min(int(p.viewport.y + p.relative_size.y + 3), len(buffer.lines) - 1)
            top := buffer.lines[culling_start][0]
            bottom := buffer.lines[culling_end][0]
            screen_buffer = buffer.str[top:bottom]
        }

        for r, index in screen_buffer {
            if r == '\n' {
                sx = 0
                sy += line_height
                continue
            }

            glyph := font_editor.glyphs[r]

            if r >= 32 && r < 128 {
                src := sdl.Rect{ glyph.x, glyph.y, glyph.w, glyph.h }
                dest := sdl.FRect{
                    f32(sx + glyph.xoffset),
                    f32(sy + glyph.yoffset) - y_offset_for_centering,
                    f32(glyph.w), f32(glyph.h),
                }

                set_fg(font_editor.texture, default)
                sdl.RenderCopyF(renderer, font_editor.texture, &src, &dest)
            }

            sx += glyph.xadvance
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

        if focused && !bragi.ui_pane.enabled {
            if !caret.blinking {
                sdl.RenderFillRectF(renderer, &dest)

                rune_behind_cursor = ' '

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
                    render_copy(font_editor.texture, &glyph_src, &glyph_dest)
                }
            }
        } else {
            sdl.RenderDrawRectF(renderer, &dest)
        }
    } // End Cursor

    { // Start Modeline
        PADDING :: 10
        line_number := caret.coords.y + 1
        buffer_status := get_buffer_status(buffer)
        buffer_name_indices := [2]int{
            len(buffer_status), len(buffer_status) + len(buffer.name),
        }

        lml_fmt := fmt.tprintf(
            "{0} {1} ({2}, {3})",
            get_buffer_status(buffer),
            buffer.name,
            line_number,
            caret.coords.x,
        )
        rml_fmt := fmt.tprintf(
            "{0}", settings_get_major_mode_name(buffer.major_mode),
        )
        rml_fmt_size := i32(len(rml_fmt)) * font_ui.em_width
        row := p.real_size.y - font_ui.line_height
        dest_rect := sdl.Rect{
            0, row, p.real_size.x, font_ui.line_height,
        }

        left_start_column  :: PADDING
        right_start_column := p.real_size.x - PADDING - rml_fmt_size

        if focused {
            set_bg(modeline_on_bg)
        } else {
            set_bg(modeline_off_bg)
        }

        sdl.RenderFillRect(renderer, &dest_rect)

        set_bg(modeline_off_bg)
        sdl.RenderDrawLine(
            renderer,
            0, window_height - font_ui.line_height - 1,
            window_width, window_height - font_ui.line_height - 1,
        )

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
                render_copy(used_font.texture, &src, &dest)
                x += used_font.em_width
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
                render_copy(font_ui.texture, &src, &dest)
                x += font_ui.em_width
            }
        }
    } // End Modeline

    sdl.SetRenderTarget(renderer, nil)

    sdl.RenderCopy(renderer, bragi.ctx.pane_texture, nil, &pane_dest)
    profiling_end()
}

make_rect :: proc{
    make_rect_f32,
    make_rect_i32,
}

make_rect_i32 :: #force_inline proc(x, y, w, h: i32) -> sdl.Rect {
    return sdl.Rect{ x, y, w, h }
}

make_rect_f32 :: #force_inline proc(x, y, w, h: f32) -> sdl.FRect {
    return sdl.FRect{ x, y, w, h }
}

render_fill_rect :: #force_inline proc(x, y, w, h: i32) {
    rect := make_rect(x, y, w, h)
    sdl.RenderFillRect(renderer, &rect)
}

render_copy :: proc{
    render_copy_frect,
    render_copy_rect,
}

render_copy_frect :: #force_inline proc(texture: ^sdl.Texture, src: ^sdl.Rect, dest: ^sdl.FRect) {
    sdl.RenderCopyF(renderer, texture, src, dest)
}

render_copy_rect :: #force_inline proc(texture: ^sdl.Texture, src, dest: ^sdl.Rect) {
    sdl.RenderCopy(renderer, texture, src, dest)
}
