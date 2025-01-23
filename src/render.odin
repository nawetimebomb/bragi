package main

import     "core:fmt"
import     "core:strings"
import sdl "vendor:sdl2"
import     "languages"

is_caret_showing :: #force_inline proc(caret: ^Caret, x, y: i32) -> bool {
    return !caret.hidden && caret.position.x == x && caret.position.y == y
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
        camera := pane.camera
        dims  := pane.dimensions
        focused := bragi.current_pane == &pane

        { // Start Caret
            dest_rect := sdl.Rect{
                (caret.position.x - camera.x) * char_width,
                (caret.position.y - camera.y) * line_height,
                char_width, line_height,
            }

            set_bg(cursor)

            if focused {
                if !caret.hidden {
                    sdl.RenderFillRect(renderer, &dest_rect)
                }
            } else {
                sdl.RenderDrawRect(renderer, &dest_rect)
            }
        } // End Caret

        { // Start Buffer String
            contents := strings.to_string(pane.contents)
            mm := pane.buffer.major_mode
            lexer := languages.Lexer{}
            lexer_enabled := settings_is_lexer_enabled(mm)
            lex := settings_get_lexer_proc(mm)
            x, y: i32

            for r, index in contents {
                col := (x - camera.x) * char_width
                row := (y - camera.y) * line_height
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
                    if is_caret_showing(&caret, x, y) {
                        set_fg(c.texture, background)
                    } else {
                        switch mode in pane.mode {
                        case Edit_Mode:

                        case Mark_Mode:
                            start := min(mode.begin, pane.buffer.cursor)
                            end   := max(mode.begin, pane.buffer.cursor)

                            if start <= index && index < end {
                                set_bg(region)
                                dest_rect := sdl.Rect{
                                    col, row, char_width, line_height,
                                }
                                sdl.RenderFillRect(renderer, &dest_rect)
                            }
                        }
                    }
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
                get_buffer_status(pane.buffer),
                pane.buffer.name,
                pane.caret.position.y,
                pane.caret.position.x,
            )
            rml_fmt := fmt.tprintf(
                "{0}",
                settings_get_major_mode_name(pane.buffer.major_mode),
            )
            rml_fmt_size := i32(len(rml_fmt)) * char_width
            row := window_size.y - line_height
            dest_rect := sdl.Rect{
                0, row, dims.x, line_height,
            }

            left_start_column  :: PADDING
            right_start_column := window_size.x - PADDING - rml_fmt_size

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

    { // Start Minibuffer
        switch s in bragi.global_state {
        case Global_State_None:

        case Global_State_Search:
            assert(bragi.minibuffer != nil)
            row := window_size.y - line_height * 8
            prompt := strings.to_string(bragi.miniprompt)
            mfmt :=fmt.tprintf(
                "Search in buffer {0}: {1}",
                s.target.buffer.name, prompt,
            )
            col: i32
            dest_rect := sdl.Rect{
                0, row,
                window_size.x, line_height,
            }
            set_bg(highlight)
            sdl.RenderFillRect(renderer, &dest_rect)
            set_bg(modeline_on_bg)
            sdl.RenderDrawRect(renderer, &dest_rect)

            content_rect := sdl.Rect{
                0, row + line_height,
                window_size.x, line_height * 6,
            }
            set_bg(background)
            sdl.RenderFillRect(renderer, &content_rect)

            for r, index in mfmt {
                c := bragi.ctx.characters[r]
                c.dest.x = col
                c.dest.y = row

                set_fg(c.texture, background)
                sdl.RenderCopy(renderer, c.texture, nil, &c.dest)
                col += char_width
            }
        }
        // switch m in pane.mode {
        // case Edit_Mode:

        // case Search_Mode:
        //     row := dims.y - line_height
        //     minibuffer := strings.to_string(pane.minibuffer)
        //     sm_fmt := fmt.tprintf("Search: {0}", minibuffer)

        //     for r, index in sm_fmt {
        //         c := bragi.ctx.characters[r]
        //         c.dest.x = c.dest.w * i32(index)
        //         c.dest.y = row

        //         set_fg(c.texture, default)
        //         sdl.RenderCopy(renderer, c.texture, nil, &c.dest)
        //     }
        // case Mark_Mode:
        //     start := min(pane.buffer.cursor, m.begin)
        //     end   := max(pane.buffer.cursor, m.begin)
        //     count_of_marked_characters := end - start
        //     mm_fmt := fmt.tprintf("marked: {0}", count_of_marked_characters)
        //     fmt_length := i32(len(mm_fmt))
        //     dest_rect := sdl.Rect{
        //         dims.x - fmt_length * char_width,
        //         dims.y - line_height,
        //         char_width * fmt_length, line_height,
        //     }

        //     set_bg(background)
        //     sdl.RenderFillRect(renderer, &dest_rect)

        //     for r, index in mm_fmt {
        //         c := bragi.ctx.characters[r]
        //         c.dest.x =
        //             dims.x - fmt_length * char_width + i32(index) * char_width
        //         c.dest.y = dims.y - line_height

        //         set_fg(c.texture, default)
        //         sdl.RenderCopy(renderer, c.texture, nil, &c.dest)
        //     }
        // }
    } // End Minibuffer

    sdl.RenderPresent(renderer)
}
