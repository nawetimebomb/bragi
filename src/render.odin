package main

import     "core:fmt"
import     "core:strings"
import sdl "vendor:sdl2"
import     "languages"

is_caret_showing :: #force_inline proc(p: ^Pane, x, y: i32) -> bool {
    caret := p.content.caret
    return !caret.blinking && caret.coords.x == x && caret.coords.y == y
}

set_bg :: #force_inline proc(c: Color) {
    if c.a != 0 {
        sdl.SetRenderDrawColor(bragi.ctx.renderer, c.r, c.g, c.b, c.a)
    }
}

set_fg :: #force_inline proc(t: ^sdl.Texture, c: Color) {
    if c.a != 0 {
        sdl.SetTextureColorMod(t, c.r, c.g, c.b)
    }
}

render_pane :: proc(p: ^Pane, index: int, focused: bool) {
    colors := &bragi.settings.colorscheme_table
    char_width, line_height := get_standard_character_size()
    renderer := bragi.ctx.renderer
    window_size := bragi.ctx.window_size
    pane_dest := sdl.Rect{ p.real_size.x * i32(index), 0, p.real_size.x, p.real_size.y }
    viewport := p.viewport
    caret := p.content.caret
    buffer := p.content.buffer

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
        sdl.RenderDrawLine(renderer, 0, 0, 0, window_size.y)
    }

    { // Start Caret
        dest_rect := sdl.Rect{
            (caret.coords.x - viewport.x) * char_width,
            (caret.coords.y - viewport.y) * line_height,
            char_width, line_height,
        }

        set_bg(cursor)

        if focused {
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

        for r, index in buffer.str {
                col := (x - viewport.x) * char_width
                row := (y - viewport.y) * line_height
                c := bragi.ctx.characters[r]
                c.dest.x = col
                c.dest.y = row

                if lexer_enabled {
                    switch lexer.state {
                    case .Default:
                        set_fg(c.texture, default)
                    case .Builtin:
                        set_fg(c.texture, builtin)
                    case .Comment:
                        set_fg(c.texture, comment)
                    case .Constant:
                        set_fg(c.texture, constant)
                    case .Keyword:
                        set_fg(c.texture, keyword)
                    case .Highlight:
                        set_fg(c.texture, highlight)
                    case .String:
                        set_fg(c.texture, string)
                    }
                } else {
                    set_fg(c.texture, default)
                }

                if focused {
                    if is_caret_showing(p, x, y) {
                        set_fg(c.texture, background)
                    }
                    // else {
                        // switch mode in p.mode {
                        // case Edit_Mode:

                        // case Mark_Mode:
                        //     start := min(mode.begin, p.input.buf.cursor)
                        //     end   := max(mode.begin, p.input.buf.cursor)

                        //     if start <= index && index < end {
                        //         set_bg(region)
                        //         dest_rect := sdl.Rect{
                        //             col, row, char_width, line_height,
                        //         }
                        //         sdl.RenderFillRect(renderer, &dest_rect)
                        //     }
                        // }
                    // }
                }

                sdl.RenderCopy(renderer, c.texture, nil, &c.dest)

                x += 1
                if r == '\n' {
                    x = 0
                    y += 1
                }
            }
    } // End Buffer

    { // Start Modeline
        PADDING :: 10

        lml_fmt := fmt.tprintf(
            "{0} {1}  Ln: {2} Col: {3}",
            get_buffer_status(buffer),
            buffer.name,
            caret.coords.y,
            caret.coords.x,
        )
        rml_fmt := fmt.tprintf(
            "{0}",
            settings_get_major_mode_name(buffer.major_mode),
        )
        rml_fmt_size := i32(len(rml_fmt)) * char_width
        row := window_size.y - line_height
        dest_rect := sdl.Rect{
            0, row, p.real_size.x, line_height,
        }

        left_start_column  :: PADDING
        right_start_column := p.real_size.x - PADDING - rml_fmt_size

        if focused {
            set_bg(modeline_on_bg)
        } else {
            set_bg(modeline_off_bg)
        }

        sdl.RenderFillRect(renderer, &dest_rect)

        for r, index in lml_fmt {
            c := bragi.ctx.characters[r]
            c.dest.x = left_start_column + c.dest.w * i32(index)
            c.dest.y = row

            set_fg(c.texture, focused ? modeline_on_fg : modeline_off_fg)
            sdl.RenderCopy(renderer, c.texture, nil, &c.dest)
        }

        for r, index in rml_fmt {
            c := bragi.ctx.characters[r]
            c.dest.x = right_start_column + c.dest.w * i32(index)
            c.dest.y = row

            set_fg(c.texture, focused ? modeline_on_fg : modeline_off_fg)
            sdl.RenderCopy(renderer, c.texture, nil, &c.dest)
        }
    } // End Modeline

    sdl.SetRenderTarget(renderer, nil)

    sdl.RenderCopy(renderer, bragi.ctx.pane_texture, nil, &pane_dest)
}
