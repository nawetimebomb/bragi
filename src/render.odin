package main

import     "core:fmt"
import     "core:strings"
import sdl "vendor:sdl2"
import     "languages"

is_caret_showing :: #force_inline proc(p: ^Pane, x, y: i32) -> bool {
    return !p.caret.blinking && p.caret.pos.x == x && p.caret.pos.y == y
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
        caret := p.caret
        dest_rect := sdl.Rect{
            (caret.pos.x - viewport.x) * char_width,
            (caret.pos.y - viewport.y) * line_height,
            char_width, line_height,
        }

        set_bg(cursor)

        if focused {
            if !p.caret.blinking {
                sdl.RenderFillRect(renderer, &dest_rect)
            }
        } else {
            sdl.RenderDrawRect(renderer, &dest_rect)
        }
    } // End Caret

    { // Start Buffer
        mm := p.input.buf.major_mode
        lexer := languages.Lexer{}
        lexer_enabled := settings_is_lexer_enabled(mm)
        lex := settings_get_lexer_proc(mm)
        x, y: i32

        for r, index in p.input.buf.str {
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

    sdl.SetRenderTarget(renderer, nil)

    sdl.RenderCopy(renderer, bragi.ctx.pane_texture, nil, &pane_dest)
}


render :: proc() {
    colors := &bragi.settings.colorscheme_table
    char_width, line_height := get_standard_character_size()
    renderer := bragi.ctx.renderer
    window_size := bragi.ctx.window_size

    // Colors
    background      := colors[.background]
    cursor          := colors[.cursor]
    builtin         := colors[.builtin]
    comment         := colors[.comment]
    constant        := colors[.constant]
    default         := colors[.default]
    highlight       := colors[.highlight]
    keyword         := colors[.keyword]
    region          := colors[.region]
    string          := colors[.string]

    modeline_off_bg := colors[.modeline_off_bg]
    modeline_off_fg := colors[.modeline_off_fg]
    modeline_on_bg  := colors[.modeline_on_bg]
    modeline_on_fg  := colors[.modeline_on_fg]

    set_bg(background)
    sdl.RenderClear(bragi.ctx.renderer)

    for &pane in bragi.panes {
        caret := pane.caret
        viewport := pane.viewport
        dims  := pane.real_size
        origin := pane.origin
        focused := bragi.current_pane == &pane

        { // Start Caret
            dest_rect := sdl.Rect{
                (caret.pos.x - viewport.x) * char_width,
                (caret.pos.y - viewport.y) * line_height,
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

        { // Start Buffer String
            contents := strings.to_string(pane.input.str)
            mm := pane.input.buf.major_mode
            lexer := languages.Lexer{}
            lexer_enabled := settings_is_lexer_enabled(mm)
            lex := settings_get_lexer_proc(mm)
            x, y: i32

            for r, index in contents {
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
                    if is_caret_showing(&pane, x, y) {
                        set_fg(c.texture, background)
                    }
                    // else {
                        // switch mode in pane.mode {
                        // case Edit_Mode:

                        // case Mark_Mode:
                        //     start := min(mode.begin, pane.input.buf.cursor)
                        //     end   := max(mode.begin, pane.input.buf.cursor)

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
        } // End Buffer String

        { // Start Modeline
            PADDING :: 20

            lml_fmt := fmt.tprintf(
                "{0} {1}  Ln: {2} Col: {3}",
                get_buffer_status(pane.input.buf),
                pane.input.buf.name,
                pane.caret.pos.y,
                pane.caret.pos.x,
            )
            rml_fmt := fmt.tprintf(
                "{0}",
                settings_get_major_mode_name(pane.input.buf.major_mode),
            )
            rml_fmt_size := i32(len(rml_fmt)) * char_width
            row := window_size.y - line_height
            dest_rect := sdl.Rect{
                0, row, dims.x, line_height,
            }

            left_start_column  :: PADDING
            right_start_column := dims.x - PADDING - rml_fmt_size

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
    }

    sdl.RenderPresent(renderer)
}
