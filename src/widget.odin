package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

WIDGET_HEIGHT_IN_ROWS :: 15
NAMESPACE_WIDGET_SEARCH_RESULTS :: "widget.search_results"

Widget_Action :: enum {
    Find_Buffer,
    Find_File,
    Save_File_As,
    Search_In_Buffer,
}

Widget :: struct {
    active:                bool,
    cursor:                Widget_Cursor,
    cursor_selecting:      bool,
    cursor_showing:        bool,
    cursor_blink_timer:    time.Tick,

    // the selected line or -1 if selecting the prompt
    action:                Widget_Action,
    all_results:           [dynamic]Widget_Result, // the one to keep
    view_results:          []Widget_Result,        // the one to show, filtered and sorted
    results_need_update:   bool,
    prompt:                strings.Builder,
    prompt_question:       string,
    ask_for_confirmation:  bool,

    font:                  ^Font,
    texture:               ^Texture,
    rect:                  Rect,
    y_offset:              int,
}

Widget_Cursor :: struct {
    pos, sel, index: int,
}

Widget_Result :: struct {
    format:     string,
    highlights: [dynamic]Range,
    value:      Widget_Result_Value,
}

Widget_Result_Value :: union {
    Widget_Result_Buffer,
    Widget_Result_File,
    Widget_Result_Offset,
}

Widget_Result_Buffer :: ^Buffer

Widget_Result_File :: struct {
    name:     string,
    filepath: string,
    is_dir:   bool,
}

Widget_Result_Offset :: int

widget_init :: proc() {
    global_widget.font = fonts_map[.UI_Regular]

    update_widget_texture()
}

update_widget_texture :: proc() {
    assert(global_widget.font != nil)
    texture_destroy(global_widget.texture)
    widget_height := global_widget.font.line_height * WIDGET_HEIGHT_IN_ROWS
    global_widget.rect = make_rect(0, window_height - widget_height, window_width, widget_height)
    global_widget.texture = texture_create(.TARGET, i32(global_widget.rect.w), i32(global_widget.rect.h))
}

widget_open_find_buffer :: proc() {
    _widget_open()

    global_widget.action = .Find_Buffer
    global_widget.prompt_question = "Switch to"

    for buffer in open_buffers {
        if active_pane.buffer.uuid == buffer.uuid do continue
        append(&global_widget.all_results, Widget_Result{
            format     = _get_find_buffer_format(buffer),
            value      = buffer,
        })
    }

    // prefer most recent edited buffers... (not stable sorting but mostly cosmetic, not really important)
    slice.sort_by(global_widget.all_results[:], proc(a: Widget_Result, b: Widget_Result) -> bool {
        buf1, buf2 := a.value.(^Buffer), b.value.(^Buffer)
        return time.tick_since(buf1.last_edit_time) < time.tick_since(buf2.last_edit_time)
    })

    // ...but append the current active buffer last
    append(&global_widget.all_results, Widget_Result{
        format = _get_find_buffer_format(active_pane.buffer),
        value  = active_pane.buffer,
    })

    global_widget.view_results = slice.clone(global_widget.all_results[:])
}

widget_open_find_file :: proc() {
    _widget_open()

    current_dir := base_working_dir
    if active_pane.buffer.filepath != "" {
        current_dir = filepath.dir(active_pane.buffer.filepath, context.temp_allocator)
    }

    if !os.is_dir(current_dir) {
        current_dir = base_working_dir
    }

    strings.write_string(&global_widget.prompt, current_dir)

    when ODIN_OS == .Windows {
        if !strings.ends_with(current_dir, "\\") {
            strings.write_string(&global_widget.prompt, "\\")
        }
    } else {
        if !strings.ends_with(current_dir, "/") {
            strings.write_string(&global_widget.prompt, "/")
        }
    }

    _widget_find_file_open_and_read_dir(current_dir)

    global_widget.action = .Find_File
    global_widget.prompt_question = "Find file"
}

widget_open_save_file_as :: proc() {
    // this is like find file, but with a different prompt and a
    // different submit functionality. This will basically set the
    // current buffer's filepath to whatever the user selects.
    widget_open_find_file()
    global_widget.action = .Save_File_As
    global_widget.prompt_question = "Save file as"
}

widget_open_search_in_buffer :: proc() {
    _widget_open()

    global_widget.view_results = make([]Widget_Result, 0)
    global_widget.action = .Search_In_Buffer
    global_widget.prompt_question = "Search"
}

@(private="file")
_widget_find_file_open_and_read_dir :: proc(current_dir: string) {
    // cleaning up because it was called from an already existing opened widget
    if len(global_widget.all_results) > 0 {
        _clean_up_view_results()
        for r in global_widget.all_results {
            delete(r.format)
            #partial switch v in r.value {
                case Widget_Result_File: delete(v.filepath)
            }
        }
        clear(&global_widget.all_results)
    }

    if !os.is_dir(current_dir) {
        global_widget.view_results = slice.clone(global_widget.all_results[:])
        return
    }

    dir_handle, dir_open_error := os.open(current_dir)
    if dir_open_error != nil {
        log.fatalf("failed to open directory '{}' with error {}", current_dir, dir_open_error)
        widget_close()
        return
    }
    defer os.close(dir_handle)
    file_infos, read_dir_error := os.read_dir(dir_handle, 0, context.temp_allocator)

    if read_dir_error != nil {
        log.fatalf("failed to read directory '{}' with error {}", current_dir, read_dir_error)
        widget_close()
        return
    }

    for file_info in file_infos {
        fullpath := strings.clone(file_info.fullpath)

        append(&global_widget.all_results, Widget_Result{
            format    = _get_find_file_format(file_info),
            value     = Widget_Result_File{
                filepath = fullpath,
                name     = filepath.base(fullpath),
                is_dir   = file_info.is_dir,
            },
        })
    }

    slice.sort_by_key(global_widget.all_results[:], proc(key: Widget_Result) -> string {
        return key.format
    })

    global_widget.view_results = slice.clone(global_widget.all_results[:])

    global_widget.cursor.pos = len(global_widget.prompt.buf)
    global_widget.cursor.sel = global_widget.cursor.pos
}

@(private="file")
_get_filtered_all_results_with_current_query :: proc(test_query: string) -> []Widget_Result{
    profiling_start("filter all results with query")
    view_results_temp := make([dynamic]Widget_Result, 0, len(global_widget.all_results), context.temp_allocator)
    queries := strings.split(test_query, " ", context.temp_allocator)

    for item in global_widget.all_results {
        result := item
        should_process := true

        for query in queries {
            if len(query) == 0 do continue
            if !strings.contains(item.format, query) {
                should_process = false
                break
            }
        }

        // skip as one of the query components is not present in this result
        if !should_process do continue

        for query in queries {
            if len(query) == 0 do continue
            test_str := item.format
            start := strings.index(item.format, query)
            original_len := len(item.format)
            query_len := len(query)

            for start != -1 && len(test_str) > query_len {
                start += original_len - len(test_str)
                end := start + query_len
                append(&result.highlights, Range{start, end})
                test_str = item.format[end:]
                start = strings.index(test_str, query)
            }
        }

        if len(result.highlights) > 0 do append(&view_results_temp, result)
    }
    profiling_end()

    return slice.clone(view_results_temp[:])
}

@(private="file")
_clean_up_view_results :: #force_inline proc() {
    for &result in global_widget.view_results do delete(result.highlights)
    delete(global_widget.view_results)
}

// NOTE(nawe) a generic procedure to make sure we clean up opened
// widget (if any) and set the defaults again
@(private="file")
_widget_open :: proc() {
    if global_widget.active do widget_close()

    global_widget.all_results = make([dynamic]Widget_Result, 0, WIDGET_HEIGHT_IN_ROWS)
    global_widget.cursor.pos = 0
    global_widget.cursor.sel = 0
    global_widget.cursor.index = -1
    global_widget.active = true
    global_widget.ask_for_confirmation = false
    flag_pane(active_pane, {.Need_Full_Repaint})
}

widget_close :: proc() {
    if !global_widget.active do return
    global_widget.active = false

    for r in global_widget.all_results {
        delete(r.format)

        switch v in r.value {
        case Widget_Result_Buffer:
        case Widget_Result_File:
            delete(v.filepath)
        case Widget_Result_Offset:
        }
    }

    delete(global_widget.all_results)
    _clean_up_view_results()

    clear(&active_pane.regions)
    strings.builder_destroy(&global_widget.prompt)
}

widget_keyboard_event_handler :: proc(event: Event_Keyboard, cmd: Command) -> (handled: bool) {
    cursor := &global_widget.cursor

    _remove_selection :: proc() {
        cursor := &global_widget.cursor

        if cursor.pos != cursor.sel {
            low := min(cursor.pos, cursor.sel)
            high := max(cursor.pos, cursor.sel)
            remove_range(&global_widget.prompt.buf, low, high)
            cursor.pos, cursor.sel = low, low
            global_widget.cursor_selecting = false
        }
    }

    if event.is_text_input {
        if cursor.pos != cursor.sel {
            _remove_selection()
        }

        inject_at(&global_widget.prompt.buf, cursor.pos, ..transmute([]byte)event.text)
        cursor.pos += len(event.text)
        cursor.sel = cursor.pos
        global_widget.results_need_update = true
        global_widget.cursor_selecting = false
        return true
    }

    word_delim_bytes := [?]byte{'\\', '/', '_', ' ', '.'}
    prompt := strings.to_string(global_widget.prompt)

    if global_widget.ask_for_confirmation && event.key_code != .K_ENTER {
        global_widget.ask_for_confirmation = false
    }

    #partial switch event.key_code {
        case .K_BACKSPACE: {
            if cursor.pos != cursor.sel {
                _remove_selection()
                return true
            }

            start := max(cursor.pos - 1, 0)

            if .Ctrl in event.modifiers || .Alt in event.modifiers {
                for start > 0 && slice.contains(word_delim_bytes[:], prompt[start-1])  do start -= 1
                for start > 0 && !slice.contains(word_delim_bytes[:], prompt[start-1]) do start -= 1
            }

            end := cursor.pos
            remove_range(&global_widget.prompt.buf, start, end)
            cursor.pos = start
            cursor.sel = start
            global_widget.results_need_update = true
            global_widget.cursor_selecting = false
            return true
        }
        case .K_DELETE: {
            if cursor.pos != cursor.sel {
                _remove_selection()
                return true
            }

            start := cursor.pos
            end := min(cursor.pos + 1, len(prompt))

            if .Ctrl in event.modifiers || .Alt in event.modifiers {
                end = len(prompt)
            }

            remove_range(&global_widget.prompt.buf, start, end)
            global_widget.results_need_update = true
            global_widget.cursor_selecting = false
            return true
        }
    }

    #partial switch cmd {
        case .toggle_selection_mode: {
            if global_widget.cursor_selecting {
                cursor.sel = cursor.pos
            }

            global_widget.cursor_selecting = !global_widget.cursor_selecting
            return true

        }
        case .select_all: {
            cursor.pos = 0
            cursor.sel = len(prompt)
            return true
        }
        case .move_start, .move_beginning_of_line, .select_start, .select_beginning_of_line: {
            cursor.pos = 0
            if cmd != .select_start && cmd != .select_beginning_of_line && !global_widget.cursor_selecting {
                cursor.sel = 0
            }
            return true
        }
        case .move_end, .move_end_of_line, .select_end, .select_end_of_line: {
            cursor.pos = len(prompt)
            if cmd != .select_end && cmd != .select_end_of_line && !global_widget.cursor_selecting {
                cursor.sel = len(prompt)
            }
            return true
        }
        case .move_up, .select_up: {
            cursor.index -= 1
            if cursor.index < -1 do cursor.index = len(global_widget.view_results) - 1
            return true
        }
        case .move_down, .select_down: {
            cursor.index += 1
            if cursor.index >= len(global_widget.view_results) do cursor.index = 0
            return true
        }
        case .move_left, .select_left: {
            cursor.pos -= 1
            for cursor.pos > 0 && is_continuation_byte(prompt[cursor.pos]) do cursor.pos -= 1
            cursor.pos = max(cursor.pos, 0)

            if cmd != .select_left && !global_widget.cursor_selecting {
                cursor.sel = cursor.pos
            }
            return true
        }
        case .move_right, .select_right: {
            cursor.pos += 1
            for cursor.pos < len(prompt) && is_continuation_byte(prompt[cursor.pos]) do cursor.pos += 1
            cursor.pos = min(cursor.pos, len(prompt) - 1)
            if cmd != .select_right && !global_widget.cursor_selecting {
                cursor.sel = cursor.pos
            }
            return true
        }
        case .move_prev_word, .move_prev_paragraph, .select_prev_word, .select_prev_paragraph: {
            for cursor.pos > 0 && slice.contains(word_delim_bytes[:], prompt[cursor.pos-1])  do cursor.pos -= 1
            for cursor.pos > 0 && !slice.contains(word_delim_bytes[:], prompt[cursor.pos-1]) do cursor.pos -= 1
            if cmd != .select_prev_word && cmd != .select_prev_paragraph && !global_widget.cursor_selecting {
                cursor.sel = cursor.pos
            }
            return true
        }
        case .move_next_word, .move_next_paragraph, .select_next_word, .select_next_paragraph: {
            for cursor.pos < len(prompt) && !slice.contains(word_delim_bytes[:], prompt[cursor.pos]) do cursor.pos += 1
            for cursor.pos < len(prompt) && slice.contains(word_delim_bytes[:], prompt[cursor.pos])  do cursor.pos += 1
            if cmd != .select_next_word && cmd != .select_next_paragraph && !global_widget.cursor_selecting {
                cursor.sel = cursor.pos
            }
            return true
        }

        case .cut_line: {
            cursor.sel = len(prompt)
            _remove_selection()
            return true
        }
    }

    switch global_widget.action {
    case .Find_Buffer:      handled = find_buffer_keyboard_event_handler     (event, cmd)
    case .Find_File:        handled = find_file_keyboard_event_handler       (event, cmd)
    case .Save_File_As:     handled = save_file_as_keyboard_event_handler    (event, cmd)
    case .Search_In_Buffer: handled = search_in_buffer_keyboard_event_handler(event, cmd)
    }

    return
}

find_buffer_keyboard_event_handler :: proc(event: Event_Keyboard, cmd: Command) -> bool {
    cursor := &global_widget.cursor

    #partial switch event.key_code {
        case .K_ENTER, .K_TAB: {
            if cursor.index > -1 {
                result := global_widget.view_results[cursor.index]
                buffer := result.value.(^Buffer)
                switch_to_buffer(active_pane, buffer)
                widget_close()
                return true
            } else {
                if len(global_widget.prompt.buf) == 0 {
                    // TODO(nawe) proper visual error handling here
                    log.error("can't submit buffer selection without a buffer name")
                    return true
                }
                buffer := buffer_get_or_create_empty(strings.to_string(global_widget.prompt))
                switch_to_buffer(active_pane, buffer)
                widget_close()
                return true
            }
        }
    }

    #partial switch cmd {
        case .modifier: return true // handled as a modifier which is valid in this context
    }

    return false
}

find_file_keyboard_event_handler :: proc(event: Event_Keyboard, cmd: Command) -> bool {
    cursor := &global_widget.cursor

    #partial switch event.key_code {
        case .K_ENTER, .K_TAB: {
            if cursor.index > -1 {
                result := global_widget.view_results[cursor.index]
                file_info := result.value.(Widget_Result_File)

                if file_info.is_dir {
                    current_dir := filepath.clean(file_info.filepath, context.temp_allocator)
                    strings.builder_reset(&global_widget.prompt)
                    strings.write_string(&global_widget.prompt, current_dir)
                    strings.write_string(&global_widget.prompt, "/")
                    cursor.index = -1
                    _widget_find_file_open_and_read_dir(current_dir)
                } else {
                    data, success := os.read_entire_file(file_info.filepath, context.temp_allocator)
                    if !success {
                        log.fatalf("failed to read file '{}'", file_info.filepath)
                        widget_close()
                        return true
                    }
                    buffer := buffer_get_or_create_from_file(file_info.filepath, data)
                    switch_to_buffer(active_pane, buffer)
                    widget_close()
                }

                return true
            } else {
                fullpath := strings.to_string(global_widget.prompt)
                _, name_from_fullpath := filepath.split(fullpath)

                if len(fullpath) == 0 || len(name_from_fullpath) == 0 {
                    log.errorf("cannot create empty file")
                    return true
                } else {
                    // if the prompt is a file that is being viewed
                    // but is not selected, search it, select it and
                    // resubmit the event.
                    for result, index in global_widget.view_results {
                        file_info := result.value.(Widget_Result_File)

                        if file_info.filepath == fullpath {
                            cursor.index = index
                            return find_file_keyboard_event_handler(event, cmd)
                        }
                    }

                    // if it wasn't, create the buffer for the new file.
                    buffer := buffer_get_or_create_from_file(fullpath, {})
                    switch_to_buffer(active_pane, buffer)
                    widget_close()
                    return true
                }
            }
        }
    }

    return false
}

save_file_as_keyboard_event_handler :: proc(event: Event_Keyboard, cmd: Command) -> bool {
    cursor := &global_widget.cursor

    #partial switch event.key_code {
        case .K_ENTER, .K_TAB: {
            new_fullpath := strings.to_string(global_widget.prompt)

            if global_widget.ask_for_confirmation && event.key_code == .K_ENTER {
                buffer_save_as(active_pane.buffer, new_fullpath)
                widget_close()
                return true
            }

            if cursor.index > -1 {
                result := global_widget.view_results[cursor.index]
                file_info := result.value.(Widget_Result_File)

                if file_info.is_dir {
                    current_dir := filepath.clean(file_info.filepath, context.temp_allocator)
                    strings.builder_reset(&global_widget.prompt)
                    strings.write_string(&global_widget.prompt, current_dir)
                    strings.write_string(&global_widget.prompt, "/")
                    cursor.index = -1
                    _widget_find_file_open_and_read_dir(current_dir)
                } else {
                    strings.builder_reset(&global_widget.prompt)
                    strings.write_string(&global_widget.prompt, file_info.filepath)
                    cursor.pos = len(global_widget.prompt.buf)
                    cursor.sel = cursor.pos
                    cursor.index = -1
                    global_widget.ask_for_confirmation = true
                }

                return true
            } else {
                _, name_from_fullpath := filepath.split(new_fullpath)

                if len(new_fullpath) == 0 || len(name_from_fullpath) == 0 {
                    log.errorf("cannot create empty file")
                    return true
                } else {
                    // if the prompt already exists in the results,
                    // select it and resubmit the event
                    for result, index in global_widget.view_results {
                        file_info := result.value.(Widget_Result_File)

                        if file_info.filepath == new_fullpath {
                            cursor.index = index
                            return save_file_as_keyboard_event_handler(event, cmd)
                        }
                    }

                    // or just save if it wasn't in the results
                    buffer_save_as(active_pane.buffer, new_fullpath)
                    widget_close()
                }

                return true
            }
        }
    }

    return false
}

search_in_buffer_keyboard_event_handler :: proc(event: Event_Keyboard, cmd: Command) -> bool {
    cursor := &global_widget.cursor

    #partial switch event.key_code {
        case .K_ENTER, .K_TAB: {
            pane_cursor := get_first_active_cursor(active_pane)
            pane_cursor.sel = pane_cursor.pos
            widget_close()
            return true
        }
    }

    #partial switch cmd {
        case .search_backward: {
            cursor.index -= 1
            if cursor.index < 0 do cursor.index = len(global_widget.view_results) - 1
            return true
        }
        case .search_forward: {
            cursor.index += 1
            if cursor.index >= len(global_widget.view_results) do cursor.index = 0
            return true
        }
    }

    return false
}

@(private="file")
_find_buffer_widget_update :: proc() {
    cursor := &global_widget.cursor

    if cursor.index > -1 {
        item := global_widget.view_results[cursor.index]
        buffer := item.value.(^Buffer)

        if active_pane.buffer != buffer {
            switch_to_buffer(active_pane, buffer)
        }
    }

    if !global_widget.results_need_update do return

    global_widget.results_need_update = false
    _clean_up_view_results()
    query := strings.to_string(global_widget.prompt)

    if len(query) > 0 {
        global_widget.view_results = _get_filtered_all_results_with_current_query(query)
    } else {
        global_widget.view_results = slice.clone(global_widget.all_results[:])
    }
    cursor.index = len(global_widget.view_results) > 0 ? 0 : -1
}

@(private="file")
_find_or_save_file_widget_update :: proc() {
    if !global_widget.results_need_update do return
    global_widget.results_need_update = false

    cursor := &global_widget.cursor
    query := strings.to_string(global_widget.prompt)
    query_starting_index := strings.index(query, "/~/")

    if query_starting_index != -1 || strings.starts_with(query, "~/") {
        query_first_part: string

        when ODIN_OS == .Windows {
            query_first_part = base_working_dir
        } else {
            value, found := os.lookup_env("HOME", context.temp_allocator)
            query_first_part = found ? value : base_working_dir
        }

        query = fmt.tprintf("{}/{}", query_first_part, query[query_starting_index + 3:])
        strings.builder_reset(&global_widget.prompt)
        strings.write_string(&global_widget.prompt, query)
    }

    if len(query) > 0 {
        current_dir := filepath.dir(query, context.temp_allocator)
        matches_previous_dir := false

        if len(global_widget.all_results) > 0 {
            previous_result_to_test := global_widget.all_results[0]
            file_to_test := previous_result_to_test.value.(Widget_Result_File)
            previous_dir := filepath.dir(file_to_test.filepath, context.temp_allocator)
            matches_previous_dir = current_dir == previous_dir
        }

        if !matches_previous_dir {
            _widget_find_file_open_and_read_dir(current_dir)
        }

        _clean_up_view_results()

        // only care about the last part as it is the part shown in the format
        query_replaced, _ := filepath.to_slash(query, context.temp_allocator)
        last_slash_index := max(strings.last_index_byte(query_replaced, '/'), 0)
        last_part_of_query := query[last_slash_index + 1:]

        if len(last_part_of_query) > 0 {
            global_widget.view_results = _get_filtered_all_results_with_current_query(last_part_of_query)
        } else {
            global_widget.view_results = slice.clone(global_widget.all_results[:])
        }

        cursor.index = len(global_widget.view_results) > 0 ? 0 : -1
    } else {
        _clean_up_view_results()

        if len(global_widget.all_results) > 0 {
            global_widget.view_results = slice.clone(global_widget.all_results[:])
        } else {
            strings.write_string(&global_widget.prompt, base_working_dir)
            _widget_find_file_open_and_read_dir(base_working_dir)
        }
    }
}

@(private="file")
_search_in_buffer_widget_update :: proc() {
    cursor := &global_widget.cursor
    query := strings.to_string(global_widget.prompt)
    query_len := len(query)

    if cursor.index > -1 {
        result := global_widget.view_results[cursor.index]
        offset := result.value.(int)
        pane_cursor := get_first_active_cursor(active_pane)
        pane_cursor.pos = offset + query_len
        pane_cursor.sel = offset
        maybe_recenter_cursor(active_pane, true)
    }

    if !global_widget.results_need_update do return
    global_widget.results_need_update = false

    if len(query) == 0 {
        _clean_up_view_results()
        global_widget.view_results = make([]Widget_Result, 0)
    }

    // don't do anything if there's no content where we can search
    if len(active_pane.contents) == 0 || len(query) == 0 do return

    // cleaning up because it was called from an already existing opened widget
    if len(global_widget.all_results) > 0 {
        _clean_up_view_results()
        for r in global_widget.all_results do delete(r.format)
        clear(&global_widget.all_results)
        clear(&active_pane.regions)
    }

    buf := active_pane.contents
    buf_len := len(buf)
    left_index := 0
    right_index := buf_len - 1

    for left_index < right_index && right_index > 0 {
        // left side
        if buf[left_index] == query[0] && left_index + query_len < buf_len {
            test_word := buf[left_index:left_index + query_len]
            if query == test_word {
                result := Widget_Result{
                    format = _get_search_in_buffer_format(left_index),
                    value  = left_index,
                }
                append(&result.highlights, Range{0, query_len})
                append(&global_widget.all_results, result)

                append(&active_pane.regions, Highlight{
                    namespace  = NAMESPACE_WIDGET_SEARCH_RESULTS,
                    start      = left_index,
                    end        = left_index + query_len,
                    background = .search_background,
                    foreground = .search_foreground,
                })

                left_index += query_len
            }
        }

        // right side
        if buf[right_index] == query[0] && right_index + query_len < buf_len {
            test_word := buf[right_index:right_index + query_len]
            if query == test_word {
                result := Widget_Result{
                    format = _get_search_in_buffer_format(right_index),
                    value  = right_index,
                }
                append(&result.highlights, Range{0, query_len})
                append(&global_widget.all_results, result)

                append(&active_pane.regions, Highlight{
                    namespace  = NAMESPACE_WIDGET_SEARCH_RESULTS,
                    start      = right_index,
                    end        = right_index + query_len,
                    background = .search_background,
                    foreground = .search_foreground,
                })
            }
        }

        left_index += 1
        right_index -= 1
    }

    slice.sort_by(global_widget.all_results[:], proc(a: Widget_Result, b: Widget_Result) -> bool {
        offset1, offset2 := a.value.(int), b.value.(int)
        return offset1 < offset2
    })

    global_widget.view_results = slice.clone(global_widget.all_results[:])
    cursor.index = len(global_widget.view_results) > 0 ? 0 : -1
}

update_and_draw_widget :: proc() {
    if !global_widget.active do return

    cursor := &global_widget.cursor

    if time.tick_diff(last_keystroke, time.tick_now()) < CURSOR_RESET_TIMEOUT {
        global_widget.cursor_showing = true
        global_widget.cursor_blink_timer = time.tick_now()
    }

    if time.tick_diff(global_widget.cursor_blink_timer, time.tick_now()) > CURSOR_BLINK_TIMEOUT {
        global_widget.cursor_showing = !global_widget.cursor_showing
        global_widget.cursor_blink_timer = time.tick_now()
    }

    for cursor.index > WIDGET_HEIGHT_IN_ROWS - 2 + global_widget.y_offset do global_widget.y_offset += 1
    for cursor.index < global_widget.y_offset do global_widget.y_offset -= 1
    if  cursor.index <= 0 do global_widget.y_offset = 0

    switch global_widget.action {
    case .Find_Buffer:              _find_buffer_widget_update()
    case .Find_File, .Save_File_As: _find_or_save_file_widget_update()
    case .Search_In_Buffer:         _search_in_buffer_widget_update()
    }

    set_target(global_widget.texture)
    set_color(.background)
    prepare_for_drawing()
    prompt_ask_str := fmt.tprintf(
        "{}/{}  {}: ",
        cursor.index + 1,
        len(global_widget.view_results),
        global_widget.prompt_question,
    )

    font_regular := global_widget.font
    font_bold := fonts_map[.UI_Bold]
    line_height := font_regular.line_height
    left_padding := font_regular.xadvance
    results_pen := Vector2{left_padding, line_height}

    results_pen.y -= i32(global_widget.y_offset) * line_height

    for &result, index in global_widget.view_results {
        if results_pen.y > WIDGET_HEIGHT_IN_ROWS * line_height do break

        if results_pen.y < line_height {
            results_pen.y += line_height
            continue
        }

        is_selected := cursor.index == index

        if is_selected {
            set_color(.ui_selection_background)
            draw_rect(0, results_pen.y, i32(global_widget.rect.w), line_height, true)
        }

        results_pen = draw_highlighted_text(
            font_regular, font_bold, .foreground, .ui_selection_background, .ui_selection_foreground,
            results_pen, result.format, result.highlights[:], is_selected,
        )
    }

    prompt_query_str := strings.to_string(global_widget.prompt)

    set_color(.ui_border)
    draw_line(0, 0, i32(global_widget.rect.w), 0)
    draw_line(0, line_height, i32(global_widget.rect.w), line_height)

    if global_widget.ask_for_confirmation {
        question: string

        switch global_widget.action {
        case .Find_Buffer:
        case .Find_File:
        case .Save_File_As: question = fmt.tprintf("Overwrite: {}? ", prompt_query_str)
        case .Search_In_Buffer:
        }

        set_colors(.highlight, {font_bold.texture, font_regular.texture})
        prompt_pen := draw_text(font_bold, {left_padding, 0}, question)
        draw_text(font_regular, prompt_pen, "<ENTER>")
    } else {
        if cursor.index == -1 {
            set_color(.ui_selection_background)
            draw_rect(0, 0, i32(len(prompt_ask_str)) * font_bold.xadvance, line_height, true)
            set_color(.ui_selection_foreground, font_bold.texture)
        } else {
            set_color(.highlight, font_bold.texture)
        }

        set_color(.foreground, font_regular.texture)
        prompt_ask_pen := draw_text(font_bold, {left_padding, 0}, prompt_ask_str)
        draw_text_line(font_regular, prompt_ask_pen, prompt_query_str, {start = cursor.pos, end = cursor.sel})

        cursor_pen := prompt_ask_pen
        cursor_pen.x += prepare_text(font_regular, prompt_query_str[:cursor.pos])
        rune_behind_cursor := ' '
        if cursor.pos < len(prompt_query_str) {
            rune_behind_cursor = utf8.rune_at(prompt_query_str, cursor.pos)
        }
        draw_cursor(font_regular, cursor_pen, rune_behind_cursor, global_widget.cursor_showing, true, true)
    }

    set_target()
    draw_texture(global_widget.texture, nil, &global_widget.rect)
}

@(private="file")
_get_find_buffer_format :: proc(buffer: ^Buffer) -> string {
    MAX_NAME_LENGTH :: 24
    MIN_PADDING     :: 5

    result := strings.builder_make(context.temp_allocator)
    truncated_name := buffer.name

    if len(buffer.name) > MAX_NAME_LENGTH {
        truncated_name = fmt.tprintf("{}...", buffer.name[:MAX_NAME_LENGTH - MIN_PADDING])
    }

    strings.write_string(&result, strings.left_justify(truncated_name, MAX_NAME_LENGTH, " ", context.temp_allocator))
    strings.write_string(&result, buffer.filepath)
    strings.write_byte(&result, '\n')
    return strings.clone(strings.to_string(result))
}

@(private="file")
_get_find_file_format :: proc(file: os.File_Info) -> string {
    result := strings.builder_make(context.temp_allocator)
    strings.write_string(&result, file.name)
    if file.is_dir do strings.write_string(&result, "/")
    strings.write_byte(&result, '\n')
    return strings.clone(strings.to_string(result))
}

@(private="file")
_get_search_in_buffer_format :: proc(offset: int) -> string {
    MAX_LENGTH  :: 60
    MIN_PADDING :: 5

    pane := active_pane
    start := offset
    end := start
    coords := cursor_offset_to_coords(pane, get_lines_array(pane), offset)

    for r in pane.contents[start:] {
        if r == '\n' do break
        if end - start == MAX_LENGTH do break
        end += 1
    }

    search_result := fmt.tprintf("{}...", pane.contents[start:end])
    line_column := fmt.tprintf("({}, {})", coords.row + 1, coords.column)

    result := strings.builder_make(context.temp_allocator)
    strings.write_string(&result, strings.left_justify(
        search_result, MAX_LENGTH + MIN_PADDING, " ", context.temp_allocator,
    ))
    strings.write_string(&result, line_column)
    strings.write_string(&result, "\n")
    return strings.clone(strings.to_string(result))
}
