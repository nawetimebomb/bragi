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

Widgets_Action :: enum {
    NONE,
    BUFFERS,
    FILES,
    SEARCH_IN_BUFFER,
    SEARCH_REVERSE_IN_BUFFER,
}

Pane_State :: struct {
    buffer: ^Buffer,
    cursor_pos: int,
}

Result_Cursor_Pos :: int
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

Widgets :: struct {
    action :            Widgets_Action,
    cursor_showing:     bool,
    cursor_last_update: time.Tick,
    cursor:             int,
    selection:          int,
    did_select:         bool,
    query:              strings.Builder,
    results:            [dynamic]Result,

    enabled:            bool,
    prev_state:         Pane_State,
    columns_offset:     [MAX_VIEW_COLUMNS]int,
    target:             ^Pane,

    texture:            Texture,
    rect:               Rect,
    yoffset:            int,
}

widgets_init :: proc() {
    widgets_pane.query = strings.builder_make()
    widgets_pane.results = make([dynamic]Result, 0)
}

widgets_destroy :: proc() {
    clear_results()
    strings.builder_destroy(&widgets_pane.query)
    delete(widgets_pane.results)
}

widgets_update_draw :: proc() {
    if !widgets_pane.enabled { return }

    if widgets_pane.selection > widgets_pane.yoffset + VIEWPORT_MAX_ITEMS {
        widgets_pane.yoffset = widgets_pane.selection - VIEWPORT_MAX_ITEMS
    } else if widgets_pane.selection < widgets_pane.yoffset {
        widgets_pane.yoffset = widgets_pane.selection
    }

    widgets_pane.yoffset = max(0, widgets_pane.yoffset)

    switch widgets_pane.action {
    case .NONE:
    case .BUFFERS:
        item := widgets_pane.results[widgets_pane.selection]
        if !item.invalid {
            widgets_pane.target.buffer = item.value.(Result_Buffer_Pointer)
        }
    case .FILES:
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        item := widgets_pane.results[widgets_pane.selection]

        if !item.invalid {
            cursor_pos := item.value.(Result_Cursor_Pos)
            buffer := widgets_pane.target.buffer

            // Find the index of the cursor in the current selection
            found := -1
            for cursor, index in buffer.cursors {
                if cursor.pos == cursor_pos {
                    found = index
                    break
                }
            }

            if found != -1 {
                promote_cursor_index(buffer, found)
            } else {
                log.errorf("Failed to find buffer cursor in {0}", buffer.name)
            }
        }
    }

    font := &font_ui
    font_bold := &font_ui_bold

    set_renderer_target(widgets_pane.texture)
    clear_background(colorscheme[.background])

    profiling_start("widgets.odin:widgets_update_draw -> Render results")
    selected_line := widgets_pane.selection - widgets_pane.yoffset

    for item, line_index in widgets_pane.results[widgets_pane.yoffset:] {
        COLUMN_PADDING := 2 * font_ui.em_width

        row := i32(line_index) * font.line_height
        hl_start := item.highlight[0]
        hl_end := item.highlight[1]
        has_highlight := hl_start != hl_end
        sx: i32

        if selected_line == line_index {
            set_bg(colorscheme[.highlight_line])
            draw_rect(0, row, widgets_pane.rect.w, font.line_height)
        }

        if item.invalid {
            draw_text(font_ui, item.format, .default, sx, row)
        } else {
            splits := strings.split(item.format, "\n", context.temp_allocator)
            offset: i32

            for index in 0..<MAX_VIEW_COLUMNS {
                col_string := splits[index]
                face: Face

                switch index {
                case 0: face = .default
                case 1: face = .highlight
                case 2: face = .keyword
                case 3: face = .constant
                }

                if index == 0 {
                    draw_text_with_highlight(
                        font_ui, font_ui_bold,
                        col_string, .default, .highlight,
                        hl_start, hl_end, 0, row,
                    )
                } else {
                    padding := i32(index) * COLUMN_PADDING
                    draw_text(
                        font_ui, col_string, face,
                        padding + offset * font_ui.em_width, row,
                    )
                }

                offset += i32(widgets_pane.columns_offset[index])
            }

        }
    }
    profiling_end()

    profiling_start("widgets.odin:widgets_update_draw -> Render prompt")
    query := strings.to_string(widgets_pane.query)
    prompt_fmt := fmt.tprintf(
        "({0}/{1}) {2}: ",
        widgets_pane.selection + 1,
        len(widgets_pane.results),
        get_prompt_text(),
    )
    prompt_y := widgets_pane.rect.h - font_ui.line_height

    set_bg(colorscheme[.background])
    draw_rect(
        0, widgets_pane.rect.h - font_ui.line_height,
        widgets_pane.rect.w, font_ui.line_height,
    )

    // Draw the prompt and the query
    sx := draw_text(font_ui_bold, prompt_fmt, .highlight, 0, prompt_y)
    draw_text(font_ui, query, .default, sx, prompt_y)

    cursor_rect := make_rect(
        get_text_size(font_ui, prompt_fmt), prompt_y,
        font_ui.em_width, font_ui.line_height,
    )
    cursor_rect.x += get_text_size(font_ui, query[:widgets_pane.cursor])
    char_behind_cursor : byte = ' '

    if widgets_pane.cursor < len(query) {
        char_behind_cursor = query[widgets_pane.cursor]
    }

    draw_cursor(font_ui, {}, cursor_rect, true, char_behind_cursor, .cursor)

    set_renderer_target()
    draw_copy(widgets_pane.texture, nil, &widgets_pane.rect)
    profiling_end()
}

rollback_to_prev_value :: proc() {
    switch widgets_pane.action {
    case .NONE:
    case .BUFFERS:
        widgets_pane.target.buffer = widgets_pane.prev_state.buffer
    case .FILES:
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        buffer := widgets_pane.target.buffer
        cursor_pos := widgets_pane.prev_state.cursor_pos
        delete_all_cursors(buffer, make_cursor(cursor_pos))
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

widgets_show :: proc(target: ^Pane, action: Widgets_Action) {
    editor_keyboard_quit(target)
    cursor_pos := get_last_cursor_pos(target.buffer)

    widgets_pane.action = action
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
    if widgets_pane.enabled {
        clear_results()

        if !widgets_pane.did_select {
            rollback_to_prev_value()
        }

        widgets_pane.enabled = false
        widgets_pane.action = .NONE
        widgets_pane.cursor = 0
        widgets_pane.selection = 0
        widgets_pane.did_select = false
        widgets_pane.prev_state = {}
        widgets_pane.target = nil

        strings.builder_reset(&widgets_pane.query)
        resize_panes()
    }
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
            widgets_pane.cursor = len(query)
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
            clear(&b.cursors)

            // This happens on the target pane, so we want to make it think we're
            // also sending them keystrokes
            widgets_pane.target.last_keystroke = time.tick_now()

            if case_sensitive {
                s = strings.clone(b.str, context.temp_allocator)
            } else {
                s = strings.to_lower(b.str, context.temp_allocator)
            }

            for strings.contains(s, query) {
                found_index := strings.index(s, query)
                cursor_pos := len(b.str) - len(s) + found_index + len(query)

                start := cursor_pos - len(query)
                for start > 0 && !is_common_delimiter(b.str[start - 1]) { start -= 1 }
                end := start + 1
                for end < len(b.str) && !is_common_delimiter(b.str[end]) { end += 1 }
                hl_word := b.str[start:end]
                start_hl := strings.index(hl_word, query)

                result := Result{
                    format    = widgets_get_search_row_format(b, cursor_pos, hl_word),
                    highlight = { start_hl, start_hl + len(query) },
                    value     = cursor_pos,
                }

                new_cursor := make_cursor(cursor_pos)
                new_cursor.sel -= len(query)

                if widgets_pane.action == .SEARCH_REVERSE_IN_BUFFER {
                    inject_at(&widgets_pane.results, 0, result)
                    inject_at(&b.cursors, 0, new_cursor)
                } else {
                    append(&widgets_pane.results, result)
                    append(&b.cursors, new_cursor)
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

    widgets_pane.selection =
        clamp(widgets_pane.selection, 0, len(widgets_pane.results) - 1)
    widgets_pane.yoffset = 0
}

ui_do_command :: proc(cmd: Command, p: ^Pane, data: any) {
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

ui_delete_to :: proc(t: Cursor_Translation) {
    previous_pos := widgets_pane.cursor
    ui_move_to(t)
    current_pos := widgets_pane.cursor
    start := min(previous_pos, current_pos)
    end   := max(previous_pos, current_pos)
    remove_range(&widgets_pane.query.buf, start, end)
    filter_results()
}

ui_move_to :: proc(t: Cursor_Translation) {
    w := &widgets_pane
    query := strings.to_string(w.query)

    #partial switch t {
        case .DOWN:         w.selection = min(w.selection + 1, len(w.results) - 1)
        case .UP:           w.selection = max(w.selection - 1, 0)
        case .LEFT:         w.cursor = max(w.cursor - 1, 0)
        case .RIGHT:        w.cursor = min(w.cursor + 1, len(query))
        case .BUFFER_START,
            .LINE_START:    w.cursor = 0
        case .BUFFER_END,
            .LINE_END:      w.cursor = len(query)
        case .WORD_START: {
            for w.cursor > 0 &&
                is_common_delimiter(query[w.cursor - 1])  { w.cursor -= 1 }
            for w.cursor > 0 &&
                !is_common_delimiter(query[w.cursor - 1]) { w.cursor -= 1 }
        }
        case .WORD_END: {
            for w.cursor < len(query) &&
                is_common_delimiter(query[w.cursor])  { w.cursor += 1 }
            for w.cursor < len(query) &&
                !is_common_delimiter(query[w.cursor]) { w.cursor += 1 }
        }
    }
}

ui_select :: proc() {
    widgets_pane.did_select = true
    handled := true
    query := strings.to_string(widgets_pane.query)
    item := widgets_pane.results[widgets_pane.selection]

    switch widgets_pane.action {
    case .NONE:
    case .BUFFERS:
        if item.invalid {
            widgets_pane.target.buffer = add(buffer_init(query, 0))
        }

        widgets_hide()
    case .FILES:
        if item.invalid {
            _, filename := get_dir_and_filename_from_fullpath(query)
            widgets_pane.target.buffer = add(buffer_init(filename, 0))
        } else {
            f := item.value.(Result_File_Info)

            if f.is_dir {
                strings.builder_reset(&widgets_pane.query)
                strings.write_string(&widgets_pane.query, f.filepath)
                strings.write_string(&widgets_pane.query, "\\")
                widgets_pane.selection = 0
                widgets_pane.cursor = len(widgets_pane.query.buf)
                filter_results()
                handled = false
            } else {
                editor_open_file(widgets_pane.target, f.filepath)
            }
        }
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        buffer := widgets_pane.target.buffer

        if item.invalid {
            last_pos := widgets_pane.prev_state.cursor_pos
            delete_all_cursors(buffer, make_cursor(last_pos))
        } else {
            cursor_pos := item.value.(Result_Cursor_Pos)
            delete_all_cursors(buffer, make_cursor(cursor_pos))
        }
    }

    if handled {
        widgets_hide()
    }
}

ui_self_insert :: proc(s: string) {
    if ok, _ := inject_at(&widgets_pane.query.buf, widgets_pane.cursor, s); ok {
        widgets_pane.cursor += len(s)
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
    widgets_pane.columns_offset = {}

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
    co := &widgets_pane.columns_offset
    co[0] = max(cl0, co[0])
    co[1] = max(cl1, co[1])
    co[2] = max(cl2, co[2])
    co[3] = max(cl3, co[3])
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

widgets_get_search_row_format :: #force_inline proc(b: ^Buffer, pos: int, word_found: string) -> string {
    coords := get_coords(b, b.lines[:], pos)
    c0 := word_found
    c1 := fmt.tprintf("{0}:{1}", coords.line + 1, coords.column)
    c2 := ""
    c3 := ""

    { // c2
        line_start := get_line_start_after_indent(b, b.lines[:], coords.line)
        line_end := line_start
        for line_end < len(b.str) && b.str[line_end] != '\n' { line_end += 1 }
        c2 = b.str[line_start:line_end]
    }

    widgets_set_column_sizes(len(c0), len(c1), len(c2), len(c3))
    return fmt.aprintf("{0}\n{1}\n{2}\n{3}", c0, c1, c2, c3)
}
