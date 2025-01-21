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
    char_size := get_standard_character_size()
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
        focused := bragi.current_pane == &pane

        { // Start Caret
            dest_rect := sdl.Rect{
                (caret.position.x - camera.x) * char_size.x,
                (caret.position.y - camera.y) * char_size.y,
                char_size.x, char_size.y,
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
            buffer_str := entire_buffer_to_string(pane.buffer)
            buffer_str_lines := strings.split_lines(buffer_str, context.temp_allocator)
            mm := pane.buffer.major_mode
            lexer := languages.Lexer{}
            lexer_enabled := settings_is_lexer_enabled(mm)
            lex := settings_get_lexer_proc(mm)
            x, y: i32

            for r, index in buffer_str {
                column := (x - camera.x) * char_size.x
                row := (y - camera.y) * char_size.y
                c := bragi.ctx.characters[r]
                c.dest.x = column
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

                            if start <= index && end > index {
                                set_bg(region)
                                dest_rect := sdl.Rect{
                                    column, row, char_size.x, char_size.y,
                                }
                                sdl.RenderFillRect(renderer, &dest_rect)
                            }
                            // Handle selection
                        case Search_Mode:
                            if len(mode.results) > 0 {
                                current := 0

                                for v in mode.results {
                                    if v <= index && v + mode.query_len > index {
                                        set_fg(c.texture, highlight)
                                        break
                                    }
                                }
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

            // for line, y_index in buffer_str_lines {
            //     for r, x_index in line {
            //         x := i32(x_index)
            //         y := i32(y_index)
            //         column := (x - camera.x) * char_size.x
            //         row := (y - camera.y) * char_size.y
            //         c := bragi.ctx.characters[r]
            //         c.dest.x = column
            //         c.dest.y = row

            //         if lexer_enabled {
            //             lexer.cursor = x_index
            //             lexer.current_rune = r
            //             lexer.line = line
            //             lexer.end_of_line = len(line)

            //             lexer.length -= 1

            //             if lexer.length <= 0 {
            //                 lex(&lexer)
            //             }

            //             switch lexer.state {
            //             case .Default:
            //                 set_fg(c.texture, default)
            //             case .Builtin:
            //                 set_fg(c.texture, builtin)
            //             case .Comment:
            //                 set_fg(c.texture, comment)
            //             case .Constant:
            //                 set_fg(c.texture, constant)
            //             case .Keyword:
            //                 set_fg(c.texture, keyword)
            //             case .Highlight:
            //                 set_fg(c.texture, highlight)
            //             case .String:
            //                 set_fg(c.texture, string)
            //             }
            //         } else {
            //             set_fg(c.texture, default)
            //         }

            //         if focused {
            //             if is_caret_showing(&caret, x, y) {
            //                 set_fg(c.texture, background)
            //             } else {
            //                 // TODO: Add Mark Mode
            //                 // TODO: Add Search Mode
            //             }
            //         }

            //         sdl.RenderCopy(renderer, c.texture, nil, &c.dest)
            //     }
            // }
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
            rml_fmt_size := i32(len(rml_fmt)) * char_size.x
            row := window_size.y - char_size.y * 2
            dest_rect := sdl.Rect{
                0, row, pane.dimensions.x, char_size.y,
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

    { // Start Message Minibuffer
        row := window_size.y - char_size.y
        dest_rect := sdl.Rect{ 0, row, window_size.x, char_size.y }
        set_bg(background)
        sdl.RenderFillRect(renderer, &dest_rect)
    } // End Message Minibuffer

    sdl.RenderPresent(bragi.ctx.renderer)
}
