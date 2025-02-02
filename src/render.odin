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
    char_width, line_height := get_standard_character_size()
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
        sdl.RenderDrawLine(renderer, 0, 0, 0, window_size_in_pixels.y)
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
            col := (x - p.viewport.x) * char_width
            row := y * line_height
            c := font_editor.chars[r]
            c.rect.x = col
            c.rect.y = row

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

            if focused && !bragi.ui_pane.enabled {
                if is_caret_showing(&caret, x, y, viewport.y) {
                    set_fg(c.texture, background)
                }
            }

            sdl.RenderCopy(renderer, c.texture, nil, &c.rect)

            x += 1
            if r == '\n' {
                x = 0
                y += 1
            }
        }
    } // End Buffer

    { // Start Modeline
        PADDING :: 10
        line_number := caret.coords.y + 1

        lml_fmt := fmt.tprintf(
            "{0} {1} ({2}, {3})",
            get_buffer_status(buffer),
            buffer.name,
            line_number,
            caret.coords.x,
        )
        rml_fmt := fmt.tprintf(
            "{0}",
            settings_get_major_mode_name(buffer.major_mode),
        )
        rml_fmt_size := i32(len(rml_fmt)) * char_width
        row := p.real_size.y - line_height
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

        set_bg(modeline_off_bg)
        sdl.RenderDrawLine(
            renderer,
            0, window_size_in_pixels.y - line_height - 1,
            window_size_in_pixels.x, window_size_in_pixels.y - line_height - 1,
        )

        for r, index in lml_fmt {
            c := font_ui.chars[r]
            c.rect.x = left_start_column + c.rect.w * i32(index)
            c.rect.y = row

            set_fg(c.texture, focused ? modeline_on_fg : modeline_off_fg)
            sdl.RenderCopy(renderer, c.texture, nil, &c.rect)
        }

        for r, index in rml_fmt {
            c := font_ui.chars[r]
            c.rect.x = right_start_column + c.rect.w * i32(index)
            c.rect.y = row

            set_fg(c.texture, focused ? modeline_on_fg : modeline_off_fg)
            sdl.RenderCopy(renderer, c.texture, nil, &c.rect)
        }
    } // End Modeline

    sdl.SetRenderTarget(renderer, nil)

    sdl.RenderCopy(renderer, bragi.ctx.pane_texture, nil, &pane_dest)
    profiling_end()
}

render_ui_pane :: proc() {
    p := &bragi.ui_pane

    if !p.enabled { return  }

    colors := &bragi.settings.colorscheme_table
    char_width, line_height := get_standard_character_size()
    viewport := p.viewport
    caret := p.caret
    query := strings.to_string(p.query)
    pane_dest := sdl.Rect{
        window_size_in_pixels.x, window_size_in_pixels.y - 6 * line_height,
        window_size_in_pixels.x, 6 * line_height,
    }

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

    { // Start Results
        profiling_start("render.odin:render_ui_pane_results")
        for item, line_index in p.results[p.viewport.y:] {
            COLUMN_PADDING :: 2
            row := window_size_in_pixels.y - p.real_size.y + i32(line_index) * line_height
            start := item.highlight[0]
            end := item.highlight[1]
            has_highlight := start != end
            row_builder := strings.builder_make(context.temp_allocator)
            cl0 := p.columns_len[0] + COLUMN_PADDING
            cl1 := cl0 + p.columns_len[1] + COLUMN_PADDING
            cl2 := cl1 + p.columns_len[2] + COLUMN_PADDING
            cl3 := cl2 + p.columns_len[3] + COLUMN_PADDING

            if item.invalid {
                strings.write_string(&row_builder, item.format)
            } else {
                splits := strings.split(item.format, "\n", context.temp_allocator)

                for col_len, col_index in p.columns_len {
                    col_str := splits[col_index]
                    justify_proc := strings.left_justify

                    if col_index == len(splits) - 1  {
                        justify_proc = strings.right_justify
                    }

                    s := justify_proc(
                        col_str,
                        col_len + COLUMN_PADDING,
                        " ",
                        context.temp_allocator,
                    )
                    strings.write_string(&row_builder, s)
                }
            }

            if p.caret.coords.y - int(p.viewport.y) == line_index {
                select_rect := sdl.Rect{ 0, row, window_size_in_pixels.x, line_height }
                set_bg(region)
                sdl.RenderFillRect(renderer, &select_rect)
            }

            for r, char_index in strings.to_string(row_builder) {
                col := i32(char_index) * char_width
                c := font_ui.chars[r]
                c.rect.x = col
                c.rect.y = row

                if !item.invalid {
                    if has_highlight && start <= char_index && end > char_index {
                        set_fg(c.texture, highlight)
                    } else if char_index >= cl1 {
                        set_fg(c.texture, keyword)
                    } else if char_index >= cl0 {
                        set_fg(c.texture, highlight)
                    } else {
                        set_fg(c.texture, default)
                    }
                } else {
                    set_fg(c.texture, default)
                }

                sdl.RenderCopy(renderer, c.texture, nil, &c.rect)
            }
        }

        profiling_end()
    } // End Results

    { // Start Prompt
        prompt_rect := sdl.Rect{
            0, window_size_in_pixels.y - line_height, window_size_in_pixels.x, line_height,
        }
        prompt_fmt := fmt.tprintf(
            "({0}/{1}) {2}: ",
            p.caret.coords.y + 1,
            len(p.results),
            p.prompt_text,
        )
        full_fmt := fmt.tprintf("{0}{1}", prompt_fmt, query)
        row := window_size_in_pixels.y - line_height

        set_bg(background)
        sdl.RenderFillRect(renderer, &prompt_rect)

        cursor_rect := sdl.Rect{
            i32(caret.coords.x + len(prompt_fmt)) * char_width, row,
            char_width, line_height,
        }

        if !caret.blinking {
            set_bg(cursor)
            sdl.RenderFillRect(renderer, &cursor_rect)
        }

        for r, index in full_fmt {
            col := i32(index) * char_width
            c := font_ui.chars[r]
            c.rect.x = col
            c.rect.y = row

            if index < len(prompt_fmt) {
                set_fg(c.texture, highlight)
            } else if is_caret_showing(&caret, i32(index - len(prompt_fmt)), 0, 0) {
                set_fg(c.texture, background)
            } else {
                set_fg(c.texture, default)
            }

            sdl.RenderCopy(renderer, c.texture, nil, &c.rect)
        }
    } // End Prompt
}
