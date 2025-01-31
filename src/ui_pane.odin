package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:time"

VIEWPORT_MAX_ITEMS :: 8
UI_PANE_SIZE :: 10

UI_View_Column_Proc :: #type proc(Result_Value) -> string

UI_View_Justify :: enum { left, center, right }

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

Result_View_Column :: struct {
    justify:    UI_View_Justify,
    length:     int,
    value_proc: UI_View_Column_Proc,
}

Result_Caret_Pos :: Caret_Pos
Result_Buffer_Pointer :: ^Buffer

Result_File :: struct {
    filepath: string,
    is_dir:   bool,
    mod_time: time.Time,
    name:     string,
    size:     i64,
}

Result_Value :: union {
    Result_Buffer_Pointer,
    Result_Caret_Pos,
    Result_File,
}

Result :: struct {
    highlight:      Caret_Pos,
    invalid_result: bool,
    value:          Result_Value,
}

UI_Pane :: struct {
    action:          UI_Pane_Action,
    caret:           Caret,
    enabled:         bool,
    did_select:      bool,
    prev_state:      Pane_State,
    query:           strings.Builder,
    view_columns:    [dynamic]Result_View_Column,
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
    p.view_columns = make([dynamic]Result_View_Column, 0)
    p.results = make([dynamic]Result, 0)
}

ui_pane_destroy :: proc() {
    p := &bragi.ui_pane

    clear_results()
    strings.builder_destroy(&p.query)
    delete(p.view_columns)
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

        if !item.invalid_result {
            p.target.buffer = item.value.(Result_Buffer_Pointer)
        }

        sync_caret_coords(p.target)
    case .FILES:
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        item := p.results[p.caret.coords.y]

        if !item.invalid_result {
            p.target.caret.coords = item.value.(Result_Caret_Pos)
        }
    }
}

ui_pane_end :: proc() {
    p := &bragi.ui_pane

    if !p.enabled { return }
}

create_view_columns :: proc() {
    p := &bragi.ui_pane

    switch p.action {
    case .NONE:
    case .BUFFERS:
        BUF_LENGTH_LEN :: 6
        MAJOR_MODE_PADDING :: 2
        STATUS_LEN :: 10
        name_len := 0
        major_mode_len := 0

        for b in bragi.buffers {
            mms := settings_get_major_mode_name(b.major_mode)
            name_len = len(b.name) if len(b.name) > name_len else name_len
            major_mode_len = len(mms) if len(mms) > major_mode_len else major_mode_len
        }

        append(&p.view_columns,
               Result_View_Column{
                   justify    = .left,
                   length     = name_len,
                   value_proc = ui_view_column_buffer_name,
               },
               Result_View_Column{
                   justify    = .center,
                   length     = STATUS_LEN,
                   value_proc = ui_view_column_buffer_status,
               },
               Result_View_Column{
                   justify    = .left,
                   length     = BUF_LENGTH_LEN,
                   value_proc = ui_view_column_buffer_len,
               },
               Result_View_Column{
                   justify    = .left,
                   length     = major_mode_len + MAJOR_MODE_PADDING,
                   value_proc = ui_view_column_buffer_major_mode,
               },
               Result_View_Column{
                   value_proc = ui_view_column_buffer_filepath,
               })
    case .FILES:
        FILE_LENGTH_LEN :: 6

        append(&p.view_columns,
               Result_View_Column{
                   justify    = .left,
                   length     = 16,
                   value_proc = ui_view_column_file_name,
               },
               Result_View_Column{
                   justify    = .left,
                   length     = FILE_LENGTH_LEN,
                   value_proc = ui_view_column_file_len,
               })
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        append(&p.view_columns,
               Result_View_Column{
                   justify    = .left,
                   length     = 16,
                   value_proc = ui_view_column_highlighted_word,
               },
               Result_View_Column{
                   justify    = .left,
                   length     = 9,
                   value_proc = ui_view_column_line_column_number,
               },
               Result_View_Column{
                   value_proc = ui_view_column_whole_line,
               })
    }
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

    ui_filter_results()
    create_view_columns()
    resize_panes()
}

ui_pane_hide :: proc() {
    p := &bragi.ui_pane
    clear_results()
    clear(&p.view_columns)

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

ui_filter_results :: proc() {
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
                highlight = { start, end },
                value = &b,
            })
        }

        if query_has_value {
            append(&p.results, Result{
                invalid_result = true,
            })
        }
    case .FILES:
        if !query_has_value {
            // TODO: get directory from buffer filepath if exists
            strings.write_string(&p.query, "C:\\Code\\bragi\\")
            query = strings.to_string(p.query)
            p.caret.coords.x = len(query)
        }

        last_slash_index := strings.last_index(query, "/")

        if last_slash_index == -1 {
            last_slash_index = strings.last_index(query, "\\")
        }

        dir, filename_query := get_dir_and_filename_from_fullpath(query)

        if os.is_dir(dir) {
            v, _ := os.open(dir)
            fis, _ := os.read_dir(v, 0, context.temp_allocator)

            for f in fis {
                if !strings.contains(f.name, filename_query) {
                    continue
                }

                start := strings.index(f.name, filename_query)
                end := start + len(filename_query)

                append(&p.results, Result{
                    highlight = { start, end },
                    value = Result_File{
                        filepath = strings.clone(f.fullpath),
                        is_dir   = f.is_dir,
                        mod_time = f.modification_time,
                        name     = strings.clone(f.name),
                        size     = f.size,
                    },
                })
            }

            os.close(v)
        }

        if len(p.results) == 0 {
            append(&p.results, Result{ invalid_result = true })
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

                if p.action == .SEARCH_REVERSE_IN_BUFFER {
                    inject_at(&p.results, 0, Result{
                        highlight = { 0, len(query) },
                        value = pos,
                    })
                } else {
                    append(&p.results, Result{
                        highlight = { 0, len(query) },
                        value = pos,
                    })
                }

                s = s[found_index + len(query):]
            }

            if len(p.results) == 0 {
                append(&p.results, Result{
                    invalid_result = true,
                })
            }
        } else {
            append(&p.results, Result{
                invalid_result = true,
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
        for pos.x > 0 && is_whitespace(query[pos.x - 1])  { pos.x -= 1 }
        for pos.x > 0 && !is_whitespace(query[pos.x - 1]) { pos.x -= 1 }
    case .WORD_END:
        for pos.x < len(query) && is_whitespace(query[pos.x])  { pos.x += 1 }
        for pos.x < len(query) && !is_whitespace(query[pos.x]) { pos.x += 1 }
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
    ui_filter_results()
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

        if item.invalid_result {
            p.target.buffer = add(buffer_init(query, 0))
        }

        ui_pane_hide()
    case .FILES:
        item := p.results[p.caret.coords.y]
        if item.invalid_result {
            _, filename := get_dir_and_filename_from_fullpath(query)
            p.target.buffer = add(buffer_init(filename, 0))
        } else {
            f := item.value.(Result_File)

            if f.is_dir {
                strings.builder_reset(&p.query)
                strings.write_string(&p.query, f.filepath)
                strings.write_string(&p.query, "\\")
                p.caret.coords.y = 0
                p.caret.coords.x = len(p.query.buf)
                ui_filter_results()
                handled = false
            } else {
                editor_open_file(p.target, f.filepath)
            }
        }
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        item := p.results[p.caret.coords.y]

        if item.invalid_result {
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

    ui_filter_results()
}

ui_get_invalid_result_string :: #force_inline proc() -> string {
    p := &bragi.ui_pane
    query := strings.to_string(p.query)
    tmp := strings.builder_make(context.temp_allocator)

    switch p.action {
    case .NONE:
    case .BUFFERS:
        strings.write_string(&tmp, "Create a buffer with name ")
        strings.write_quoted_string(&tmp, query)
    case .FILES:
        dir, filename := get_dir_and_filename_from_fullpath(query)
        prefix := fmt.tprintf("Create a file in {0} with name ", dir)
        strings.write_string(&tmp, prefix)
        strings.write_quoted_string(&tmp, filename)
    case .SEARCH_IN_BUFFER, .SEARCH_REVERSE_IN_BUFFER:
        if len(query) > 0 {
            strings.write_string(&tmp, "No results found for ")
            strings.write_quoted_string(&tmp, query)
        } else {
            strings.write_string(&tmp, "Enter a query to start searching...")
        }
    }

    return strings.to_string(tmp)
}

ui_get_valid_result_string :: #force_inline proc(result: Result_Value) -> string {
    p := &bragi.ui_pane
    tmp := strings.builder_make(context.temp_allocator)
    s := ""

    for col in p.view_columns {
        s := col.value_proc(result)
        s = justify_string(col, s)
        strings.write_string(&tmp, s)
    }

    return strings.to_string(tmp)
}

ui_view_column_file_name :: #force_inline proc(result: Result_Value) -> string {
    f := result.(Result_File)
    return f.name
}

ui_view_column_file_len :: #force_inline proc(result: Result_Value) -> string {
    f := result.(Result_File)
    size := f64(f.size)
    return get_parsed_length_to_kb(size)
}

ui_view_column_highlighted_word :: #force_inline proc(result: Result_Value) -> string {
    p := &bragi.ui_pane
    b := p.target.buffer
    s := b.str
    pos := result.(Result_Caret_Pos)
    start_pos := caret_to_buffer_cursor(b, pos) - len(strings.to_string(p.query))
    end_pos := start_pos + 1
    for end_pos < len(s) && is_whitespace(s[end_pos])  { end_pos += 1 }
    for end_pos < len(s) && !is_whitespace(s[end_pos]) { end_pos += 1 }
    return s[start_pos:end_pos]
}

ui_view_column_line_column_number :: #force_inline proc(result: Result_Value) -> string {
    pos := result.(Result_Caret_Pos)
    return fmt.tprintf("{0}:{1}", pos.y + 1, pos.x)
}

ui_view_column_whole_line :: #force_inline proc(result: Result_Value) -> string {
    p := &bragi.ui_pane
    b := p.target.buffer
    pos := result.(Result_Caret_Pos)
    split := strings.split_lines(b.str, context.temp_allocator)
    return split[pos.y]
}

ui_view_column_buffer_name :: #force_inline proc(result: Result_Value) -> string {
    b := result.(Result_Buffer_Pointer)
    return b.name
}

ui_view_column_buffer_status :: #force_inline proc(result: Result_Value) -> string {
    b := result.(Result_Buffer_Pointer)
    return get_buffer_status(b)
}

ui_view_column_buffer_len :: #force_inline proc(result: Result_Value) -> string {
    b := result.(Result_Buffer_Pointer)
    length := f64(len(b.str))
    return get_parsed_length_to_kb(length)
}

ui_view_column_buffer_major_mode :: #force_inline proc(result: Result_Value) -> string {
    b := result.(Result_Buffer_Pointer)
    return settings_get_major_mode_name(b.major_mode)
}

ui_view_column_buffer_filepath :: #force_inline proc(result: Result_Value) -> string {
    b := result.(Result_Buffer_Pointer)
    return b.filepath
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

    switch p.action {
    case .NONE:
    case .BUFFERS:
    case .FILES:
        for &item in p.results {
            if !item.invalid_result {
                v := item.value.(Result_File)
                delete(v.filepath)
                delete(v.name)
            }
        }
    case .SEARCH_IN_BUFFER:
    case .SEARCH_REVERSE_IN_BUFFER:
    }

    clear(&p.results)
}
