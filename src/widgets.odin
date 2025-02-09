package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:time"

MAX_VIEW_COLUMNS :: 4
VIEWPORT_MAX_ITEMS :: 8

WIDGETS_PANE_LARGE_SIZE :: 10

Widget_Action :: enum {
    NONE,
    BUFFERS,
    FILES,
    SEARCH_IN_BUFFER,
    SEARCH_REVERSE_IN_BUFFER,
}

Pane_State :: struct {
    buffer: ^Buffer,
    cursor_pos: [2]int,
}

Result_Cursor_Pos :: [2]int
Result_Buffer_Pointer :: ^Buffer

Result_File_Info :: struct {
    filepath: string,
    is_dir:   bool,
    mod_time: time.Time,
    name:     string,
    size:     i64,
}

Result_Value :: union {
    Result_Buffer_Pointer,
    Result_Cursor_Pos,
    Result_File_Info,
}

Result :: struct {
    format:    string,
    highlight: [2]int,
    invalid:   bool,
    value:     Result_Value,
}

Widget :: struct {
    action:        Widget_Action,
    caret:         Caret,
    enabled:       bool,
    did_select:    bool,
    prev_state:    Pane_State,
    query:         strings.Builder,
    columns_len:   [MAX_VIEW_COLUMNS]int,
    results:       [dynamic]Result,
    target:        ^Pane,
    texture:       Texture,
    rect:          Rect,
    relative_size: [2]i32,
    viewport:      [2]i32,
}

widgets_init :: proc() {
    widgets_pane.relative_size = {
        window_width / char_width,
        WIDGETS_PANE_LARGE_SIZE,
    }
    widgets_pane.query = strings.builder_make()
    widgets_pane.results = make([dynamic]Result, 0)
}

widgets_destroy :: proc() {
    clear_results()
    strings.builder_destroy(&widgets_pane.query)
    delete(widgets_pane.results)
}

widgets_update_draw :: proc() {
    caret := &widgets_pane.caret

    if !widgets_pane.enabled { return }

    // if should_caret_reset_blink_timers(caret) {
    //     caret.blinking = false
    //     caret.blinking_count = 0
    //     caret.last_update = time.tick_now()
    // }

    // if should_caret_blink(caret) {
    //     caret.blinking = !caret.blinking
    //     caret.blinking_count += 1
    //     caret.last_update = time.tick_now()
    // }

    caret_y := i32(widgets_pane.caret.coords.y)

    if caret_y > widgets_pane.viewport.y + VIEWPORT_MAX_ITEMS {
        widgets_pane.viewport.y = caret_y - VIEWPORT_MAX_ITEMS
    } else if caret_y < widgets_pane.viewport.y {
        widgets_pane.viewport.y = caret_y
    }

    widgets_pane.viewport.y = max(0, widgets_pane.viewport.y)

    switch widgets_pane.action {
    case .NONE:
    case .BUFFERS:
        item := widgets_pane.results[widgets_pane.caret.coords.y]

        if !item.invalid {
            widgets_pane.target.buffer = item.value.(Result_Buffer_Pointer)
        }

        sync_caret_coords(widgets_pane.target)
    case .FILES:
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        item := widgets_pane.results[widgets_pane.caret.coords.y]

        if !item.invalid {
            cursor_pos := item.value.(Result_Cursor_Pos)
            clear(&widgets_pane.target.cursors)
            length_of_query := len(strings.to_string(widgets_pane.query))
            new_cursor := Cursor{ cursor_pos, cursor_pos }
            new_cursor.tail.x -= length_of_query
            append(&widgets_pane.target.cursors, new_cursor)
        }
    }

    widgets_draw()
}

rollback_to_prev_value :: proc() {
    switch widgets_pane.action {
    case .NONE:
    case .BUFFERS:
        widgets_pane.target.buffer = widgets_pane.prev_state.buffer
    case .FILES:
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        cursor_pos := widgets_pane.prev_state.cursor_pos
        clear(&widgets_pane.target.cursors)
        append(&widgets_pane.target.cursors, Cursor{ cursor_pos, cursor_pos })
    }
}

maybe_create_new_texture_for_widgets :: proc() {
    last_rect := widgets_pane.rect
    new_rect := make_rect()
    local_line_height := font_ui.line_height

    switch widgets_pane.action {
    case .NONE:
    case .BUFFERS, .FILES, .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        new_rect.x = 0
        new_rect.y = window_height - WIDGETS_PANE_LARGE_SIZE * local_line_height
        new_rect.w = window_width
        new_rect.h = WIDGETS_PANE_LARGE_SIZE * local_line_height
    }

    if last_rect != new_rect {
        widgets_pane.rect = new_rect
        widgets_pane.texture =
            make_texture(widgets_pane.texture, .RGBA32, .TARGET, new_rect)
    }
}

widgets_show :: proc(target: ^Pane, action: Widget_Action) {
    editor_set_buffer_cursor(target)
    cursor_pos, _ := get_last_cursor(target)

    widgets_pane.action = action
    widgets_pane.caret.coords = {}
    widgets_pane.enabled = true
    widgets_pane.target = target
    widgets_pane.prev_state = {
        buffer = target.buffer,
        cursor_pos = cursor_pos,
    }

    maybe_create_new_texture_for_widgets()
    filter_results()
    resize_panes()
}

widgets_hide :: proc() {
    clear_results()

    if !widgets_pane.did_select {
        rollback_to_prev_value()
    }

    widgets_pane.enabled = false
    widgets_pane.action = .NONE
    widgets_pane.caret.coords = {}
    widgets_pane.did_select = false
    widgets_pane.prev_state = {}
    widgets_pane.target = nil
    widgets_pane.viewport = {}

    strings.builder_reset(&widgets_pane.query)
    resize_panes()
}

filter_results :: proc() {
    query := strings.to_string(widgets_pane.query)
    query_has_value := len(query) > 0
    case_sensitive := strings.contains_any(query, UPPERCASE_CHARS)
    clear_results()

    switch widgets_pane.action {
    case .NONE:
    case .BUFFERS:
        for &b in open_buffers {
            buf_name := b.name

            if !case_sensitive {
                buf_name = strings.to_lower(b.name, context.temp_allocator)
            }

            if query_has_value {
                found := strings.contains(buf_name, query)
                if !found { continue }
            }

            start := strings.index(buf_name, query)
            end := start + len(query)

            append(&widgets_pane.results, Result{
                format    = widgets_get_buffer_row_format(&b),
                highlight = { start, end },
                value     = &b,
            })
        }

        if query_has_value {
            append(&widgets_pane.results, Result{
                format  = fmt.aprintf("Create a buffer with name \"{0}\"", query),
                invalid = true,
            })
        }
    case .FILES:
        if !query_has_value {
            // TODO: get directory from buffer filepath if exists
            if len(widgets_pane.target.buffer.filepath) > 0 {
                dir, _ := get_dir_and_filename_from_fullpath(widgets_pane.target.buffer.filepath)
                strings.write_string(&widgets_pane.query, dir)
            } else {
                strings.write_string(&widgets_pane.query, get_base_os_dir())
            }

            query = strings.to_string(widgets_pane.query)
            widgets_pane.caret.coords.x = len(query)
        }

        dir, filename_query := get_dir_and_filename_from_fullpath(query)

        if os.is_dir(dir) {
            v, _ := os.open(dir)
            fis, _ := os.read_dir(v, 0, context.temp_allocator)

            for f in fis {
                if !strings.contains(f.name, filename_query) {
                    continue
                }
                tmp_name := strings.builder_make(context.temp_allocator)

                start := strings.index(f.name, filename_query)
                end := start + len(filename_query)

                strings.write_string(&tmp_name, f.name)

                if f.is_dir {
                    strings.write_string(&tmp_name, "/")
                }

                value := Result_File_Info{
                    filepath = strings.clone(f.fullpath),
                    is_dir   = f.is_dir,
                    mod_time = f.modification_time,
                    name     = strings.clone(strings.to_string(tmp_name)),
                    size     = f.size,
                }

                append(&widgets_pane.results, Result{
                    format    = widgets_get_file_row_format(&value),
                    highlight = { start, end },
                    value     = value,
                })
            }

            os.close(v)
        }

        if len(widgets_pane.results) == 0 && len(filename_query) > 0 {
            append(&widgets_pane.results, Result{
                format  = fmt.aprintf(
                    "Create a file in {0} with name {1}", dir, filename_query,
                ),
                invalid = true,
            })
        }
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        if query_has_value {
            b := widgets_pane.target.buffer
            s := ""

            if case_sensitive {
                s = strings.clone(b.str, context.temp_allocator)
            } else {
                s = strings.to_lower(b.str, context.temp_allocator)
            }

            for strings.contains(s, query) {
                found_index := strings.index(s, query)
                cursor_pos := len(b.str) - len(s) + found_index + len(query)
                pos := buffer_cursor_to_caret(b, cursor_pos)
                result := Result{
                    format    = widgets_get_search_row_format(b, pos),
                    highlight = { 0, len(query) },
                    value     = pos,
                }

                if widgets_pane.action == .SEARCH_REVERSE_IN_BUFFER {
                    inject_at(&widgets_pane.results, 0, result)
                } else {
                    append(&widgets_pane.results, result)
                }

                s = s[found_index + len(query):]
            }

            if len(widgets_pane.results) == 0 {
                append(&widgets_pane.results, Result{
                    format  = fmt.aprintf("No results found for \"{0}\"", query),
                    invalid = true,
                })
            }
        } else {
            append(&widgets_pane.results, Result{
                format  = strings.clone("Enter a query to start searching..."),
                invalid = true,
            })
        }
    }

    widgets_pane.caret.coords.y = clamp(widgets_pane.caret.coords.y, 0, len(widgets_pane.results) - 1)
    widgets_pane.viewport.y = 0
}

ui_do_command :: proc(cmd: Command, p: ^Pane, data: any) {
    widgets_pane.caret.last_keystroke = time.tick_now()

    #partial switch cmd {
        case .search_backward:      ui_move_to(.UP)
        case .search_forward:       ui_move_to(.DOWN)

        case .ui_select:            ui_select()

        case .delete_backward_char: ui_delete_to(.LEFT)
        case .delete_backward_word: ui_delete_to(.WORD_START)
        case .delete_forward_char:  ui_delete_to(.RIGHT)
        case .delete_forward_word:  ui_delete_to(.WORD_END)

        case .beginning_of_line:    ui_move_to(.LINE_START)
        case .beginning_of_buffer:  ui_move_to(.BUFFER_START)
        case .end_of_line:          ui_move_to(.LINE_END)
        case .end_of_buffer:        ui_move_to(.BUFFER_END)

        case .backward_char:        ui_move_to(.LEFT)
        case .backward_word:        ui_move_to(.WORD_START)
        case .forward_char:         ui_move_to(.RIGHT)
        case .forward_word:         ui_move_to(.WORD_END)
        case .next_line:            ui_move_to(.DOWN)
        case .previous_line:        ui_move_to(.UP)

        case .self_insert:          ui_self_insert(data.(string))
    }
}

ui_translate :: proc(t: Caret_Translation) -> (pos: Caret_Pos) {
    pos = widgets_pane.caret.coords
    query := strings.to_string(widgets_pane.query)
    results := widgets_pane.results

    switch t {
    case .DOWN:
        pos.y += 1
        if pos.y >= len(results) {
            pos.y = 0
        }
    case .UP:
        pos.y -= 1
        if pos.y < 0 {
            pos.y = len(results) - 1
        }
    case .LEFT:
        if pos.x > 0 {
            pos.x -= 1
        }
    case .RIGHT:
        if pos.x < len(query) {
            pos.x += 1
        }
    case .BUFFER_START:
        pos.x = 0
    case .BUFFER_END:
        pos.x = len(query)
    case .LINE_START:
        pos.x = 0
    case .LINE_END:
        pos.x = len(query)
    case .WORD_START:
        for pos.x > 0 && is_common_delimiter(query[pos.x - 1])  { pos.x -= 1 }
        for pos.x > 0 && !is_common_delimiter(query[pos.x - 1]) { pos.x -= 1 }
    case .WORD_END:
        for pos.x < len(query) && is_common_delimiter(query[pos.x])  { pos.x += 1 }
        for pos.x < len(query) && !is_common_delimiter(query[pos.x]) { pos.x += 1 }
    }

    return
}

ui_delete_to :: proc(t: Caret_Translation) {
    new_pos := ui_translate(t)
    start := min(widgets_pane.caret.coords.x, new_pos.x)
    end := max(widgets_pane.caret.coords.x, new_pos.x)
    remove_range(&widgets_pane.query.buf, start, end)
    widgets_pane.caret.coords.x = start
    filter_results()
}

ui_move_to :: proc(t: Caret_Translation) {
    widgets_pane.caret.coords = ui_translate(t)
}

ui_select :: proc() {
    widgets_pane.did_select = true
    handled := true
    query := strings.to_string(widgets_pane.query)

    switch widgets_pane.action {
    case .NONE:
    case .BUFFERS:
        // NOTE: We only care about the selection with nil pointer because the other ones
        // are changed on the fly, but this one requires a new buffer to be created.
        item := widgets_pane.results[widgets_pane.caret.coords.y]

        if item.invalid {
            widgets_pane.target.buffer = add(buffer_init(query, 0))
        }

        widgets_hide()
    case .FILES:
        item := widgets_pane.results[widgets_pane.caret.coords.y]
        if item.invalid {
            _, filename := get_dir_and_filename_from_fullpath(query)
            widgets_pane.target.buffer = add(buffer_init(filename, 0))
        } else {
            f := item.value.(Result_File_Info)

            if f.is_dir {
                strings.builder_reset(&widgets_pane.query)
                strings.write_string(&widgets_pane.query, f.filepath)
                strings.write_string(&widgets_pane.query, "\\")
                widgets_pane.caret.coords.y = 0
                widgets_pane.caret.coords.x = len(widgets_pane.query.buf)
                filter_results()
                handled = false
            } else {
                editor_open_file(widgets_pane.target, f.filepath)
            }
        }
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        item := widgets_pane.results[widgets_pane.caret.coords.y]

        if item.invalid {
            cursor_pos := widgets_pane.prev_state.cursor_pos
            clear(&widgets_pane.target.cursors)
            append(&widgets_pane.target.cursors, Cursor{ cursor_pos, cursor_pos })
        } else {
            cursor := widgets_pane.target.cursors[0]
            cursor_pos := cursor.head
            clear(&widgets_pane.target.cursors)
            append(&widgets_pane.target.cursors, Cursor{ cursor_pos, cursor_pos })
        }
    }

    if handled {
        widgets_hide()
    }
}

ui_self_insert :: proc(s: string) {
    if ok, _ := inject_at(&widgets_pane.query.buf, widgets_pane.caret.coords.x, s); ok {
        widgets_pane.caret.coords.x += len(s)
    }

    filter_results()
}

get_prompt_text :: #force_inline proc() -> string {
    t := widgets_pane.target
    s := ""

    switch widgets_pane.action {
    case .NONE:
    case .BUFFERS:
        s = "Switch to"
    case .FILES:
        s = "Find file"
    case .SEARCH_IN_BUFFER:
        s = fmt.tprintf("Search forward in \"{0}\"", t.buffer.name)
    case .SEARCH_REVERSE_IN_BUFFER:
        s = fmt.tprintf("Search backward in \"{0}\"", t.buffer.name)
    }

    return s
}

clear_results :: proc() {
    widgets_pane.columns_len = { 16, 6, 6, 0 }

    for &item in widgets_pane.results {
        delete(item.format)
        if widgets_pane.action == .FILES {
            if !item.invalid {
                v := item.value.(Result_File_Info)
                delete(v.filepath)
                delete(v.name)
            }
        }
    }

    clear(&widgets_pane.results)
}

widgets_set_column_sizes :: #force_inline proc(cl0, cl1, cl2, cl3: int) {
    widgets_pane.columns_len[0] = max(cl0, widgets_pane.columns_len[0])
    widgets_pane.columns_len[1] = max(cl1, widgets_pane.columns_len[1])
    widgets_pane.columns_len[2] = max(cl2, widgets_pane.columns_len[2])
    widgets_pane.columns_len[3] = max(cl3, widgets_pane.columns_len[3])
}

widgets_get_buffer_row_format :: #force_inline proc(b: ^Buffer) -> string {
    c0 := b.name
    c1 := b.status
    c2 := settings_get_major_mode_name(b.major_mode)
    c3 := b.filepath

    widgets_set_column_sizes(len(c0), len(c1), len(c2), len(c3))
    return fmt.aprintf("{0}\n{1}\n{2}\n{3}", c0, c1, c2, c3)
}

widgets_get_file_row_format :: #force_inline proc(f: ^Result_File_Info) -> string {
    c0 := f.name
    c1 := ""
    c2 := ""
    c3 := ""

    { // c3
        HOURS_IN_A_DAY     :: 24
        HOURS_IN_A_WEEK    :: HOURS_IN_A_DAY * 7
        now := time.now()
        diff_from_now := time.diff(f.mod_time, now)
        current_year := time.year(now)
        mod_year := time.year(f.mod_time)
        hours := int(time.duration_hours(diff_from_now))
        minutes := int(time.duration_minutes(diff_from_now))

        if mod_year < current_year {
            c3 = fmt.tprintf(
                "%i %s %2i",
                mod_year,
                get_month_string(time.month(f.mod_time)),
                time.day(f.mod_time),
            )
        } else if hours > HOURS_IN_A_WEEK {
            buf: [time.MIN_HMS_LEN]u8
            c3 = fmt.tprintf(
                "%s %2i %s",
                get_month_string(time.month(f.mod_time)),
                time.day(f.mod_time),
                time.time_to_string_hms(f.mod_time, buf[:])[:5],
            )
        } else if hours > HOURS_IN_A_DAY {
            days := hours / HOURS_IN_A_DAY
            c3 = fmt.tprintf("%i %s ago", days, days > 1 ? "days" : "day")
        } else if hours > 0 {
            c3 = fmt.tprintf("%i %s ago", hours, hours > 1 ? "hours" : "hour")
        } else if minutes > 0 {
            c3 = fmt.tprintf("%i %s ago", minutes, minutes > 1 ? "minutes" : "minute")
        } else {
            c3 = "less than a minute ago"
        }
    }

    widgets_set_column_sizes(len(c0), len(c1), len(c2), len(c3))
    return fmt.aprintf("{0}\n{1}\n{2}\n{3}", c0, c1, c2, c3)
}

widgets_get_search_row_format :: #force_inline proc(b: ^Buffer, pos: Caret_Pos) -> string {
    c0 := ""
    c1 := fmt.tprintf("{0}:{1}", pos.y + 1, pos.x)
    c2 := ""
    c3 := ""

    { // c0
        start_pos := caret_to_buffer_cursor(b, pos) - len(strings.to_string(widgets_pane.query))
        end_pos := start_pos + 1
        for end_pos < len(b.str) && is_whitespace(b.str[end_pos])  { end_pos += 1 }
        for end_pos < len(b.str) && !is_whitespace(b.str[end_pos]) { end_pos += 1 }
        c0 = b.str[start_pos:end_pos]
    }

    { // c2
        line_start := get_line_start_after_indent(b, pos.y)
        line_end := line_start
        for line_end < len(b.str) && b.str[line_end] != '\n' { line_end += 1 }
        c2 = b.str[line_start:line_end]
    }

    widgets_set_column_sizes(len(c0), len(c1), len(c2), len(c3))
    return fmt.aprintf("{0}\n{1}\n{2}\n{3}", c0, c1, c2, c3)
}

widgets_draw :: proc() {
    caret := widgets_pane.caret
    colors := &bragi.settings.colorscheme_table
    font := &font_ui
    font_bold := &font_ui_bold
    viewport := widgets_pane.viewport

    set_renderer_target(widgets_pane.texture)
    clear_background(colors[.background])

    { // Start Results
        profiling_start("ui_pane.odin:widgets_render")

        for item, line_index in widgets_pane.results[widgets_pane.viewport.y:] {
            COLUMN_PADDING :: 2

            row := i32(line_index) * font.line_height
            hl_start := item.highlight[0]
            hl_end := item.highlight[1]
            has_highlight := hl_start != hl_end
            row_builder := strings.builder_make(context.temp_allocator)
            cl0 := widgets_pane.columns_len[0] + COLUMN_PADDING
            cl1 := cl0 + widgets_pane.columns_len[1] + COLUMN_PADDING
            cl2 := cl1 + widgets_pane.columns_len[2] + COLUMN_PADDING
            cl3 := cl2 + widgets_pane.columns_len[3] + COLUMN_PADDING
            x: i32

            if item.invalid {
                strings.write_string(&row_builder, item.format)
            } else {
                splits := strings.split(item.format, "\n", context.temp_allocator)

                for col_len, col_index in widgets_pane.columns_len {
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

            if caret.coords.y - int(viewport.y) == line_index {
                set_bg(colors[.highlight_line])
                draw_rect(0, row, widgets_pane.rect.w, font.line_height)
            }

            for r, char_index in strings.to_string(row_builder) {
                used_font := font

                if !item.invalid {
                    if has_highlight && hl_start <= char_index && hl_end > char_index {
                        used_font = font_bold
                        set_fg(used_font.texture, colors[.highlight])
                    } else if char_index >= cl1 {
                        set_fg(used_font.texture, colors[.keyword])
                    } else if char_index >= cl0 {
                        set_fg(used_font.texture, colors[.highlight])
                    } else {
                        set_fg(used_font.texture, colors[.default])
                    }
                }

                g := used_font.glyphs[r]
                src := make_rect(g.x, g.y, g.w, g.h)
                dest := make_rect(
                    f32(x + g.xoffset),
                    f32(row + g.yoffset) - used_font.y_offset_for_centering,
                    f32(g.w), f32(g.h),
                )
                draw_copy(used_font.texture, &src, &dest)
                x += g.xadvance
            }
        }

        profiling_end()
    } // End Results

    { // Start Prompt
        current_font := font_ui
        prompt_fmt := fmt.tprintf(
            "({0}/{1}) {2}: ", caret.coords.y + 1, len(widgets_pane.results), get_prompt_text(),
        )
        prompt_str := fmt.tprintf("{0}{1}", prompt_fmt, strings.to_string(widgets_pane.query))
        row := widgets_pane.rect.h - current_font.line_height
        x: i32

        set_bg(colors[.background])
        draw_rect(
            0, widgets_pane.rect.h - current_font.line_height,
            widgets_pane.rect.w, current_font.line_height,
        )

        if !caret.blinking {
            set_bg(colors[.cursor])
            draw_rect(
                i32(caret.coords.x + len(prompt_fmt)) * current_font.em_width, row,
                current_font.em_width, current_font.line_height,
            )
        }

        for r, index in prompt_str {
            current_font = font_ui

            if index < len(prompt_fmt) {
                current_font = font_ui_bold
                set_fg(current_font.texture, colors[.highlight])
                // TODO: Is cursor showing?
            // } else if is_caret_showing(&caret, i32(index - len(prompt_fmt)), 0, 0) {
            //     set_fg(current_font.texture, colors[.background])
            } else {
                set_fg(current_font.texture, colors[.default])
            }

            glyph := current_font.glyphs[r]
            src := make_rect(glyph.x, glyph.y, glyph.w, glyph.h)
            dest := make_rect(
                f32(x + glyph.xoffset),
                f32(row + glyph.yoffset) - current_font.y_offset_for_centering,
                f32(glyph.w), f32(glyph.h),
            )
            draw_copy(current_font.texture, &src, &dest)
            x += glyph.xadvance
        }
    } // End Prompt

    set_renderer_target()
    draw_copy(widgets_pane.texture, nil, &widgets_pane.rect)
}
