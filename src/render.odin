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

    { // Start Caret
        dest_rect := sdl.Rect{
            (i32(caret.coords.x) - viewport.x) * char_width,
            (i32(caret.coords.y) - viewport.y) * line_height,
            char_width, line_height,
        }

        set_bg(cursor)

        if focused && !bragi.ui_pane.enabled {
            if !caret.blinking {
                sdl.RenderFillRect(renderer, &dest_rect)
            }
        } else {
            sdl.RenderDrawRect(renderer, &dest_rect)
        }
    } // End Caret

    { // Start Buffer
        mm := buffer.major_mode
        lexer := languages.Lexer{}
        lexer_enabled := settings_is_lexer_enabled(mm)
        lex := settings_get_lexer_proc(mm)
        x, y: i32
        screen_buffer := buffer.str

        if len(buffer.lines) > int(p.relative_size.y) {
            culling_start := max(p.viewport.y, 0)
            culling_end :=
                min(int(p.viewport.y + p.relative_size.y + 3), len(buffer.lines) - 1)
            top := buffer.lines[culling_start]
            bottom := buffer.lines[culling_end]
            screen_buffer = buffer.str[top:bottom]
        }

        for r, index in screen_buffer {
            if r == '\n' {
                x = 0
                y += line_height
                continue
            }

            glyph_rect := font_editor.glyphs[r].rect
            dest := sdl.Rect{ x, y, glyph_rect.w, glyph_rect.h }

            set_fg(font_editor.texture, default)

            if focused && !bragi.ui_pane.enabled {
                coords_x := x / char_width
                coords_y := y / line_height

                if is_caret_showing(&caret, coords_x, coords_y, viewport.y) {
                    set_fg(font_editor.texture, background)
                }
            }

            sdl.RenderCopy(renderer, font_editor.texture, &glyph_rect, &dest)
            x += char_x_advance

            // col := x - p.viewport.x * char_width
            // row := y
            // c.rect.x = col
            // c.rect.y = row

            // if lexer_enabled {
            //     switch lexer.state {
            //     case .Default:
            //         set_fg(c.texture, default)
            //     case .Builtin:
            //         set_fg(c.texture, builtin)
            //     case .Comment:
            //         set_fg(c.texture, comment)
            //     case .Constant:
            //         set_fg(c.texture, constant)
            //     case .Keyword:
            //         set_fg(c.texture, keyword)
            //     case .Highlight:
            //         set_fg(c.texture, highlight)
            //     case .String:
            //         set_fg(c.texture, string)
            //     }
            // } else {
            //     set_fg(c.texture, default)
            // }

            // x += char_width
            // if r == '\n' {
            //     x = 0
            //     y += line_height
            // }
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
