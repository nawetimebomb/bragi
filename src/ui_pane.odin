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
UI_PANE_SIZE :: 10

UI_Pane_Action :: enum {
    NONE,
    BUFFERS,
    FILES,
    SEARCH_IN_BUFFER,
    SEARCH_REVERSE_IN_BUFFER,
}

Pane_State :: struct {
    buffer: ^Buffer,
    caret_coords: Caret_Pos,
}

Result_Caret_Pos :: Caret_Pos
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
    Result_Caret_Pos,
    Result_File_Info,
}

Result :: struct {
    format:    string,
    highlight: Caret_Pos,
    invalid:   bool,
    value:     Result_Value,
}

UI_Pane :: struct {
    action:          UI_Pane_Action,
    caret:           Caret,
    enabled:         bool,
    did_select:      bool,
    prev_state:      Pane_State,
    query:           strings.Builder,
    columns_len:     [MAX_VIEW_COLUMNS]int,
    results:         [dynamic]Result,
    prompt_text:     string,
    target:          ^Pane,
    real_size:       [2]i32,
    relative_size:   [2]i32,
    viewport:        [2]i32,
}

ui_pane_init :: proc() {
    p := &bragi.ui_pane
    window_size := bragi.ctx.window_size
    char_width, line_height := get_standard_character_size()

    p.real_size = {
        window_size.x,
        UI_PANE_SIZE * line_height,
    }
    p.relative_size = {
        window_size.x / char_width,
        UI_PANE_SIZE,
    }
    p.query = strings.builder_make()
    p.results = make([dynamic]Result, 0)
}

ui_pane_destroy :: proc() {
    p := &bragi.ui_pane

    clear_results()
    strings.builder_destroy(&p.query)
    delete(p.results)
    delete(p.prompt_text)
}

ui_pane_begin :: proc() {
    p := &bragi.ui_pane
    caret := &p.caret

    if !p.enabled { return }

    if should_caret_reset_blink_timers(caret) {
        caret.blinking = false
        caret.blinking_count = 0
        caret.last_update = time.tick_now()
    }

    if should_caret_blink(caret) {
        caret.blinking = !caret.blinking
        caret.blinking_count += 1
        caret.last_update = time.tick_now()
    }

    caret_y := i32(p.caret.coords.y)

    if caret_y > p.viewport.y + VIEWPORT_MAX_ITEMS {
        p.viewport.y = caret_y - VIEWPORT_MAX_ITEMS
    } else if caret_y < p.viewport.y {
        p.viewport.y = caret_y
    }

    p.viewport.y = max(0, p.viewport.y)

    switch p.action {
    case .NONE:
    case .BUFFERS:
        item := p.results[p.caret.coords.y]

        if !item.invalid {
            p.target.buffer = item.value.(Result_Buffer_Pointer)
        }

        sync_caret_coords(p.target)
    case .FILES:
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        item := p.results[p.caret.coords.y]

        if !item.invalid {
            p.target.caret.coords = item.value.(Result_Caret_Pos)
        }
    }
}

ui_pane_end :: proc() {
    p := &bragi.ui_pane

    if !p.enabled { return }
}

rollback_to_prev_value :: proc() {
    p := &bragi.ui_pane

    switch p.action {
    case .NONE:
    case .BUFFERS:
        p.target.buffer = p.prev_state.buffer
    case .FILES:
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        p.target.caret.coords = p.prev_state.caret_coords
    }
}

ui_pane_show :: proc(target: ^Pane, action: UI_Pane_Action) {
    editor_set_buffer_cursor(target)

    p := &bragi.ui_pane
    p.action = action
    p.caret.coords = {}
    p.enabled = true
    p.target = target
    p.prompt_text = get_prompt_text(target, action)
    p.prev_state = {
        buffer = target.buffer,
        caret_coords = target.caret.coords,
    }

    filter_results()
    resize_panes()
}

ui_pane_hide :: proc() {
    p := &bragi.ui_pane
    clear_results()

    if !p.did_select {
        rollback_to_prev_value()
    }

    p.enabled = false
    p.action = .NONE
    p.caret.coords = {}
    p.did_select = false
    p.prev_state = {}
    p.target = nil
    p.viewport = {}

    strings.builder_reset(&p.query)
    delete(p.prompt_text)
    resize_panes()
}

filter_results :: proc() {
    p := &bragi.ui_pane
    query := strings.to_string(p.query)
    query_has_value := len(query) > 0
    case_sensitive := strings.contains_any(query, UPPERCASE_CHARS)
    clear_results()

    switch p.action {
    case .NONE:
    case .BUFFERS:
        for &b in bragi.buffers {
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

            append(&p.results, Result{
                format    = ui_pane_get_buffer_row_format(&b),
                highlight = { start, end },
                value     = &b,
            })
        }

        if query_has_value {
            append(&p.results, Result{
                format  = fmt.aprintf("Create a buffer with name \"{0}\"", query),
                invalid = true,
            })
        }
    case .FILES:
        if !query_has_value {
            // TODO: get directory from buffer filepath if exists
            if len(p.target.buffer.filepath) > 0 {
                dir, _ := get_dir_and_filename_from_fullpath(p.target.buffer.filepath)
                strings.write_string(&p.query, dir)
            } else {
                strings.write_string(&p.query, get_base_os_dir())
            }

            query = strings.to_string(p.query)
            p.caret.coords.x = len(query)
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

                append(&p.results, Result{
                    format    = ui_pane_get_file_row_format(&value),
                    highlight = { start, end },
                    value     = value,
                })
            }

            os.close(v)
        }

        if len(p.results) == 0 && len(filename_query) > 0 {
            append(&p.results, Result{
                format  = fmt.aprintf(
                    "Create a file in {0} with name {1}", dir, filename_query,
                ),
                invalid = true,
            })
        }
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        if query_has_value {
            b := p.target.buffer
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
                    format    = ui_pane_get_search_row_format(b, pos),
                    highlight = { 0, len(query) },
                    value     = pos,
                }

                if p.action == .SEARCH_REVERSE_IN_BUFFER {
                    inject_at(&p.results, 0, result)
                } else {
                    append(&p.results, result)
                }

                s = s[found_index + len(query):]
            }

            if len(p.results) == 0 {
                append(&p.results, Result{
                    format  = fmt.aprintf("No results found for \"{0}\"", query),
                    invalid = true,
                })
            }
        } else {
            append(&p.results, Result{
                format  = "Enter a query to start searching...",
                invalid = true,
            })
        }
    }

    p.caret.coords.y = clamp(p.caret.coords.y, 0, len(p.results) - 1)
    p.viewport.y = 0
}

ui_do_command :: proc(cmd: Command, p: ^Pane, data: any) {
    p := &bragi.ui_pane
    p.caret.last_keystroke = time.tick_now()

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
    p := &bragi.ui_pane
    pos = p.caret.coords
    query := strings.to_string(p.query)
    results := p.results

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
    p := &bragi.ui_pane
    new_pos := ui_translate(t)
    start := min(p.caret.coords.x, new_pos.x)
    end := max(p.caret.coords.x, new_pos.x)
    remove_range(&p.query.buf, start, end)
    p.caret.coords.x = start
    filter_results()
}

ui_move_to :: proc(t: Caret_Translation) {
    p := &bragi.ui_pane
    p.caret.coords = ui_translate(t)
}

ui_select :: proc() {
    p := &bragi.ui_pane
    p.did_select = true
    handled := true
    query := strings.to_string(p.query)

    switch p.action {
    case .NONE:
    case .BUFFERS:
        // NOTE: We only care about the selection with nil pointer because the other ones
        // are changed on the fly, but this one requires a new buffer to be created.
        item := p.results[p.caret.coords.y]

        if item.invalid {
            p.target.buffer = add(buffer_init(query, 0))
        }

        ui_pane_hide()
    case .FILES:
        item := p.results[p.caret.coords.y]
        if item.invalid {
            _, filename := get_dir_and_filename_from_fullpath(query)
            p.target.buffer = add(buffer_init(filename, 0))
        } else {
            f := item.value.(Result_File_Info)

            if f.is_dir {
                strings.builder_reset(&p.query)
                strings.write_string(&p.query, f.filepath)
                strings.write_string(&p.query, "\\")
                p.caret.coords.y = 0
                p.caret.coords.x = len(p.query.buf)
                filter_results()
                handled = false
            } else {
                editor_open_file(p.target, f.filepath)
            }
        }
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        item := p.results[p.caret.coords.y]

        if item.invalid {
            p.target.caret.coords = p.prev_state.caret_coords
        }
    }

    if handled {
        ui_pane_hide()
    }
}

ui_self_insert :: proc(s: string) {
    p := &bragi.ui_pane

    if ok, _ := inject_at(&p.query.buf, p.caret.coords.x, s); ok {
        p.caret.coords.x += len(s)
    }

    filter_results()
}

get_prompt_text :: #force_inline proc(t: ^Pane, action: UI_Pane_Action) -> string {
    s := ""

    switch action {
    case .NONE:
    case .BUFFERS:
        s = "Switch to"
    case .FILES:
        s = "Find file"
    case .SEARCH_IN_BUFFER:
        s = fmt.aprintf("Search forward in \"{0}\"", t.buffer.name)
    case .SEARCH_REVERSE_IN_BUFFER:
        s = fmt.aprintf("Search backward in \"{0}\"", t.buffer.name)
    }

    return s
}

clear_results :: proc() {
    p := &bragi.ui_pane

    p.columns_len = { 16, 6, 6, 0 }

    for &item in p.results {
        delete(item.format)

        if p.action == .FILES {
            if !item.invalid {
                v := item.value.(Result_File_Info)
                delete(v.filepath)
                delete(v.name)
            }
        }
    }

    clear(&p.results)
}

ui_pane_set_column_sizes :: #force_inline proc(cl0, cl1, cl2, cl3: int) {
    p := &bragi.ui_pane

    p.columns_len[0] = cl0 if cl0 > p.columns_len[0] else p.columns_len[0]
    p.columns_len[1] = cl1 if cl1 > p.columns_len[1] else p.columns_len[1]
    p.columns_len[2] = cl2 if cl2 > p.columns_len[2] else p.columns_len[2]
    p.columns_len[3] = cl3 if cl3 > p.columns_len[3] else p.columns_len[3]
}

ui_pane_get_buffer_row_format :: #force_inline proc(b: ^Buffer) -> string {
    fmt_string := strings.builder_make(context.temp_allocator)
    c0 := b.name
    c1 := b.status
    c2 := settings_get_major_mode_name(b.major_mode)
    c3 := b.filepath

    strings.write_string(&fmt_string, c0)
    strings.write_byte(&fmt_string, '\n')
    strings.write_string(&fmt_string, c1)
    strings.write_byte(&fmt_string, '\n')
    strings.write_string(&fmt_string, c2)
    strings.write_byte(&fmt_string, '\n')
    strings.write_string(&fmt_string, c3)

    ui_pane_set_column_sizes(len(c0), len(c1), len(c2), len(c3))

    return strings.clone(strings.to_string(fmt_string))
}

ui_pane_get_file_row_format :: #force_inline proc(f: ^Result_File_Info) -> string {
    fmt_string := strings.builder_make(context.temp_allocator)
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

    strings.write_string(&fmt_string, c0)
    strings.write_byte(&fmt_string, '\n')
    strings.write_string(&fmt_string, c1)
    strings.write_byte(&fmt_string, '\n')
    strings.write_string(&fmt_string, c2)
    strings.write_byte(&fmt_string, '\n')
    strings.write_string(&fmt_string, c3)

    ui_pane_set_column_sizes(len(c0), len(c1), len(c2), len(c3))

    return strings.clone(strings.to_string(fmt_string))
}

ui_pane_get_search_row_format :: #force_inline proc(b: ^Buffer, pos: Caret_Pos) -> string {
    p := &bragi.ui_pane
    fmt_string := strings.builder_make(context.temp_allocator)
    c0 := ""
    c1 := fmt.tprintf("{0}:{1}", pos.y + 1, pos.x)
    c2 := ""
    c3 := ""

    { // c0
        start_pos := caret_to_buffer_cursor(b, pos) - len(strings.to_string(p.query))
        end_pos := start_pos + 1
        for end_pos < len(b.str) && is_whitespace(b.str[end_pos])  { end_pos += 1 }
        for end_pos < len(b.str) && !is_whitespace(b.str[end_pos]) { end_pos += 1 }
        c0 = b.str[start_pos:end_pos]
    }

    { // c2
        line_start := get_line_start_after_indent(b, pos.y)
        line_end := get_line_end(b, pos.y)
        c2 = b.str[line_start:line_end - 1]
    }

    strings.write_string(&fmt_string, c0)
    strings.write_byte(&fmt_string, '\n')
    strings.write_string(&fmt_string, c1)
    strings.write_byte(&fmt_string, '\n')
    strings.write_string(&fmt_string, c2)
    strings.write_byte(&fmt_string, '\n')
    strings.write_string(&fmt_string, c3)

    ui_pane_set_column_sizes(len(c0), len(c1), len(c2), len(c3))

    return strings.clone(strings.to_string(fmt_string))
}
