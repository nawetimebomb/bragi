package main

import     "core:fmt"
import     "core:strings"
import sdl "vendor:sdl2"

get_major_mode_name :: proc(mm: Major_Mode) -> string {
    return bragi.settings.mm[mm].name
}

set_bg :: proc(c: Color) {
    if c.a != 0 {
        sdl.SetRenderDrawColor(bragi.ctx.renderer, c.r, c.g, c.b, c.a)
    }
}

set_fg :: proc(t: ^sdl.Texture, c: Color) {
    if c.a != 0 {
        sdl.SetTextureColorMod(t, c.r, c.g, c.b)
    }
}

render :: proc() {
    colors := &bragi.settings.colors
    char_size := get_standard_character_size()
    renderer := bragi.ctx.renderer
    window_size := bragi.ctx.window_size

    // Colors
    cursor_bg       := colors[.cursor_bg]
    cursor_fg       := colors[.cursor_fg]
    default_bg      := colors[.default_bg]
    default_fg      := colors[.default_fg]
    modeline_off_bg := colors[.modeline_off_bg]
    modeline_off_fg := colors[.modeline_off_fg]
    modeline_on_bg  := colors[.modeline_on_bg]
    modeline_on_fg  := colors[.modeline_on_fg]

    set_bg(default_bg)
    sdl.RenderClear(bragi.ctx.renderer)

    for &pane in bragi.panes {
        caret := pane.caret
        camera := pane.camera
        focused := &pane == bragi.current_pane

        { // Start Caret
            dest_rect := sdl.Rect{
                (caret.position.x - camera.x) * char_size.x,
                (caret.position.y - camera.y) * char_size.y,
                char_size.x, char_size.y,
            }

            set_bg(cursor_bg)

            if focused {
                if !caret.hidden {
                    sdl.RenderFillRect(renderer, &dest_rect)
                }
            } else {
                sdl.RenderDrawRect(renderer, &dest_rect)
            }
        } // End Caret

        { // Start Buffer
            buffer_str := entire_buffer_to_string(pane.buffer)
            buffer_str_lines := strings.split_lines(buffer_str, context.temp_allocator)

            for line, y_index in buffer_str_lines {
                for r, x_index in line {
                    x := i32(x_index)
                    y := i32(y_index)
                    column := (x - camera.x) * char_size.x
                    row := (y - camera.y) * char_size.y
                    c := bragi.ctx.characters[r]
                    c.dest.x = column
                    c.dest.y = row

                    // TODO: Add lexing here so it should render by state
                    set_fg(c.texture, default_fg)

                    if focused {
                        // TODO: Add Mark Mode
                        // TODO: Add Search Mode
                    }

                    if !caret.hidden && caret.position.x == x && caret.position.y == y {
                        set_fg(c.texture, cursor_fg)
                    }

                    sdl.RenderCopy(renderer, c.texture, nil, &c.dest)
                }
            }
        } // End Buffer

        { // Start Modeline
            PADDING :: 20

            lml_fmt := fmt.tprintf(
                "{0} {1}  Ln: {2} Col: {3}",
                get_buffer_status(pane.buffer),
                pane.buffer.name,
                pane.caret.position.x,
                pane.caret.position.y,
            )
            rml_fmt := fmt.tprintf(
                "{0}",
                get_major_mode_name(pane.buffer.major_mode),
            )
            rml_fmt_size := i32(len(rml_fmt)) * char_size.x
            row := window_size.y - char_size.y * 2
            dest_rect := sdl.Rect{
                0, row, window_size.x, char_size.y,
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
        set_bg(default_bg)
        sdl.RenderFillRect(renderer, &dest_rect)
    } // End Message Minibuffer

    sdl.RenderPresent(bragi.ctx.renderer)
}
