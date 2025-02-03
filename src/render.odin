package main

import     "core:math"
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

    // { // Start Caret
    //     x := i32(caret.coords.x)
    //     y := i32(caret.coords.y)

    //     dest_rect := sdl.FRect{
    //         f32(x - viewport.x) * _font_editor.em_width,
    //         f32(y - viewport.y) * _font_editor.line_height,
    //         _font_editor.em_width, _font_editor.line_height,
    //     }

    //     set_bg(cursor)

    //     if focused && !bragi.ui_pane.enabled {
    //         if !caret.blinking {
    //             sdl.RenderFillRectF(renderer, &dest_rect)
    //         }
    //     } else {
    //         sdl.RenderDrawRectF(renderer, &dest_rect)
    //     }
    // } // End Caret

    { // Start Buffer
        mm := buffer.major_mode
        lexer := languages.Lexer{}
        lexer_enabled := settings_is_lexer_enabled(mm)
        lex := settings_get_lexer_proc(mm)
        screen_buffer := buffer.str

        if len(buffer.lines) > int(p.relative_size.y) {
            culling_start := max(p.viewport.y, 0)
            culling_end :=
                min(int(p.viewport.y + p.relative_size.y + 3), len(buffer.lines) - 1)
            top := buffer.lines[culling_start]
            bottom := buffer.lines[culling_end]
            screen_buffer = buffer.str[top:bottom]
        }

        // cursor_pos := caret_to_buffer_cursor(buffer, caret.coords)
        x: f32
        y := _font_editor.line_height
        for r, index in screen_buffer {
            if r == '\n' {
                x = 0
                y += _font_editor.line_height
                continue
            }


            if r >= 32 && r < 128 {
                char := _font_editor.chars[r - 32]
                src := sdl.Rect{
                    i32(char.x0), i32(char.y0), i32(char.x1 - char.x0), i32(char.y1 - char.y0),
                }
                dest := sdl.FRect{x + char.xoff, y + char.yoff, char.xoff2 - char.xoff, char.yoff2 - char.yoff, }

                // SDL_Rect src_rect = {info->x0, info->y0, info->x1 - info->x0, info->y1 - info->y0};
			    // SDL_Rect dst_rect = {x + info->xoff, y + info->yoff, info->x1 - info->x0, info->y1 - info->y0};
                // 	SDL_FRect dst_rect = {x + info->xoff, y + info->yoff, info.xoff2 - info.xoff, info.yoff2 - info.yoff};

                set_fg(_font_editor.texture, default)

                sdl.RenderCopyF(renderer, _font_editor.texture, &src, &dest)
                x += char.xadvance
            }
        }

        caret_x: f32
        pos := caret_to_buffer_cursor(buffer, caret.coords)

        for r, index in buffer.str {
            if r >= 32 && r < 128 {
                char := _font_editor.chars[r - 32]
                caret_x += char.xadvance
                if pos == index { break }
            }
        }

        fmt.println(caret_x, _font_editor.em_width, math.floor(f32(caret.coords.x) * _font_editor.em_width))

        dest_rect := sdl.FRect{
            caret_x,
            f32(caret.coords.y - int(p.viewport.y)) * _font_editor.line_height,
            _font_editor.em_width, _font_editor.line_height,
        }

        set_bg(cursor)

        if focused && !bragi.ui_pane.enabled {
            if !caret.blinking {
                sdl.RenderFillRectF(renderer, &dest_rect)
            }
        } else {
            sdl.RenderDrawRectF(renderer, &dest_rect)
        }
    } // End Buffer

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

                glyph_rect := used_font.glyphs[r].rect
                dest := sdl.Rect{ x, row, glyph_rect.w, glyph_rect.h }
                set_fg(used_font.texture, focused ? modeline_on_fg : modeline_off_fg)
                sdl.RenderCopy(renderer, used_font.texture, &glyph_rect, &dest)
                x += used_font.x_advance
            }
        }

        { // Right side
            x := i32(right_start_column)

            for r, index in rml_fmt {
                glyph_rect := font_ui.glyphs[r].rect
                dest := sdl.Rect{ x, row, glyph_rect.w, glyph_rect.h }
                set_fg(font_ui.texture, focused ? modeline_on_fg : modeline_off_fg)
                sdl.RenderCopy(renderer, font_ui.texture, &glyph_rect, &dest)
                x += font_ui.x_advance
            }
        }
    } // End Modeline

    sdl.SetRenderTarget(renderer, nil)

    sdl.RenderCopy(renderer, bragi.ctx.pane_texture, nil, &pane_dest)
    profiling_end()
}

make_rect :: #force_inline proc(x, y, w, h: i32) -> sdl.Rect {
    return sdl.Rect{ x, y, w, h }
}

render_fill_rect :: #force_inline proc(x, y, w, h: i32) {
    rect := make_rect(x, y, w, h)
    sdl.RenderFillRect(renderer, &rect)
}

render_copy :: #force_inline proc(texture: ^sdl.Texture, src, dest: ^sdl.Rect) {
    sdl.RenderCopy(renderer, texture, src, dest)
}
