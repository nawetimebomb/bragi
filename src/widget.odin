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

Widget_Action :: enum {
    Find_Buffer,
    Find_File,
}

Widget :: struct {
    active:              bool,
    cursor:              Cursor,
    cursor_showing:      bool,
    cursor_blink_timer:  time.Tick,

    // the selected line or -1 if selecting the prompt
    action:              Widget_Action,
    selection:           int,
    all_results:         [dynamic]Widget_Result, // the one to keep
    view_results:        []Widget_Result, // the one to show, contains the filters
    prompt:              strings.Builder,
    prompt_question:     string,

    font:                ^Font,
    texture:             ^Texture,
    rect:                Rect,
    y_offset:            int,
}

Widget_Result :: struct {
    format:    string,
    highlight: Range,
    value:     Widget_Result_Value,
}

Widget_Result_Value :: union {
    Widget_Result_Buffer,
    Widget_Result_File,
}

Widget_Result_Buffer :: ^Buffer

Widget_Result_File :: struct {
    name:     string,
    filepath: string,
    is_dir:   bool,
}

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
    widget_open()

    global_widget.action = .Find_Buffer
    global_widget.prompt_question = "Switch to"

    for buffer in open_buffers {
        if active_pane.buffer == buffer do continue
        append(&global_widget.all_results, Widget_Result{
            format    = get_find_buffer_format(buffer),
            highlight = {},
            value     = buffer,
        })
    }

    // prefer most recent edited buffers... (not stable sorting but mostly cosmetic, not really important)
    slice.sort_by(global_widget.all_results[:], proc(a: Widget_Result, b: Widget_Result) -> bool {
        current_tick := time.tick_now()
        buf1, buf2 := a.value.(^Buffer), b.value.(^Buffer)
        return time.tick_diff(buf1.last_edit_time, current_tick) < time.tick_diff(buf2.last_edit_time, current_tick)
    })

    // ...but append the current active buffer last
    append(&global_widget.all_results, Widget_Result{
        format    = get_find_buffer_format(active_pane.buffer),
        highlight = {},
        value     = active_pane.buffer,
    })

    global_widget.view_results = slice.clone(global_widget.all_results[:])
}

widget_open_find_file :: proc() {
    widget_open()

    current_dir := base_working_dir
    if active_pane.buffer.filepath != "" {
        current_dir = filepath.dir(active_pane.buffer.filepath, context.temp_allocator)
    }

    if !os.is_dir(current_dir) {
        current_dir = base_working_dir
    }

    strings.write_string(&global_widget.prompt, current_dir)
    widget_find_file_open_and_read_dir(current_dir)

    global_widget.action = .Find_File
    global_widget.prompt_question = "Find file"

}

widget_find_file_open_and_read_dir :: proc(current_dir: string) {
    // cleaning up because it was called from an already existing opened widget
    if len(global_widget.all_results) > 0 {
        delete(global_widget.view_results)
        for r in global_widget.all_results {
            delete(r.format)
            #partial switch v in r.value {
                case Widget_Result_File: delete(v.filepath)
            }
        }
        clear(&global_widget.all_results)
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
            format    = get_find_file_format(file_info),
            highlight = {},
            value     = Widget_Result_File{
                filepath = fullpath,
                name     = filepath.base(fullpath),
                is_dir   = file_info.is_dir,
            },
        })
    }

    global_widget.view_results = slice.clone(global_widget.all_results[:])
    global_widget.cursor.pos = len(global_widget.prompt.buf)
    global_widget.cursor.sel = global_widget.cursor.pos
}

// NOTE(nawe) a generic procedure to make sure we clean up opened
// widget (if any) and set the defaults again
@(private="file")
widget_open :: proc() {
    if global_widget.active do widget_close()

    global_widget.all_results = make([dynamic]Widget_Result, 0, WIDGET_HEIGHT_IN_ROWS)
    global_widget.cursor = {}
    global_widget.selection = -1
    global_widget.active = true
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
        }
    }

    delete(global_widget.all_results)
    delete(global_widget.view_results)

    strings.builder_destroy(&global_widget.prompt)
    update_all_pane_textures()
}

widget_keyboard_event_handler :: proc(event: Event_Keyboard) -> (handled: bool) {
    if event.is_text_input {
        inject_at(&global_widget.prompt.buf, global_widget.cursor.pos, ..transmute([]byte)event.text)
        global_widget.cursor.pos += len(event.text)
        return true
    }

    #partial switch event.key_code {
        case .K_BACKSPACE: {
            start := max(global_widget.cursor.pos - 1, 0)
            end := global_widget.cursor.pos
            remove_range(&global_widget.prompt.buf, start, end)
            global_widget.cursor.pos = start
            return true
        }
        case .K_DELETE: {
            start := global_widget.cursor.pos
            end := min(global_widget.cursor.pos + 1, len(global_widget.prompt.buf))
            remove_range(&global_widget.prompt.buf, start, end)
            return true
        }
    }

    cmd := map_keystroke_to_command(event.key_code, event.modifiers)

    #partial switch cmd {
        case .move_up: {
            global_widget.selection -= 1

            if global_widget.selection < -1 {
                global_widget.selection = len(global_widget.view_results) - 1
            }

            return true
        }
        case .move_down: {
            global_widget.selection += 1

            if global_widget.selection > len(global_widget.view_results) - 1 {
                global_widget.selection = 0
            }

            return true
        }
        case .move_left: {
            buf := global_widget.prompt.buf
            result := global_widget.cursor.pos
            result -= 1
            for result > 0 && is_continuation_byte(buf[result]) do result -= 1
            global_widget.cursor.pos = max(result, 0)
            return true
        }
        case .move_right: {
            buf := global_widget.prompt.buf
            result := global_widget.cursor.pos
            result += 1
            for result < len(buf) && is_continuation_byte(buf[result]) do result += 1
            global_widget.cursor.pos = min(result, len(buf))
            return true
        }
    }

    switch global_widget.action {
    case .Find_Buffer: handled = find_buffer_keyboard_event_handler(event)
    case .Find_File:   handled = find_file_keyboard_event_handler  (event)
    }

    return
}

find_buffer_keyboard_event_handler :: proc(event: Event_Keyboard) -> bool {
    #partial switch event.key_code {
        case .K_ENTER: {
            if global_widget.selection > -1 {
                result := global_widget.view_results[global_widget.selection]
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
                // TODO(nawe) create new named buffer
                unimplemented()
            }
        }
    }

    cmd := map_keystroke_to_command(event.key_code, event.modifiers)

    #partial switch cmd {
        case .modifier: return true // handled as a modifier which is valid in this context
    }

    return false
}

find_file_keyboard_event_handler :: proc(event: Event_Keyboard) -> bool {
    #partial switch event.key_code {
        case .K_ENTER: {
            if global_widget.selection > -1 {
                result := global_widget.view_results[global_widget.selection]
                file_info := result.value.(Widget_Result_File)

                if file_info.is_dir {
                    current_dir := filepath.clean(file_info.filepath, context.temp_allocator)
                    strings.builder_reset(&global_widget.prompt)
                    strings.write_string(&global_widget.prompt, current_dir)
                    strings.write_string(&global_widget.prompt, "/")
                    global_widget.selection = -1
                    widget_find_file_open_and_read_dir(current_dir)
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
                unimplemented()
            }
        }
    }

    return false
}

update_and_draw_widget :: proc() {
    if !global_widget.active do return

    if time.tick_diff(last_keystroke, time.tick_now()) < CURSOR_RESET_TIMEOUT {
        global_widget.cursor_showing = true
        global_widget.cursor_blink_timer = time.tick_now()
    }

    if time.tick_diff(global_widget.cursor_blink_timer, time.tick_now()) > CURSOR_BLINK_TIMEOUT {
        global_widget.cursor_showing = !global_widget.cursor_showing
        global_widget.cursor_blink_timer = time.tick_now()
    }

    for global_widget.selection > WIDGET_HEIGHT_IN_ROWS - 2 + global_widget.y_offset do global_widget.y_offset += 1
    for global_widget.selection < global_widget.y_offset do global_widget.y_offset -= 1
    if  global_widget.selection <= 0 do global_widget.y_offset = 0

    switch global_widget.action {
    case .Find_Buffer:
        if global_widget.selection > -1 {
            item := global_widget.view_results[global_widget.selection]
            buffer := item.value.(^Buffer)

            if active_pane.buffer != buffer {
                switch_to_buffer(active_pane, buffer)
            }
        }
    case .Find_File:
    }

    set_target(global_widget.texture)
    set_color(.background)
    prepare_for_drawing()
    prompt_ask_str := fmt.tprintf(
        "{}/{}  {}: ",
        global_widget.selection + 1,
        len(global_widget.view_results),
        global_widget.prompt_question,
    )

    font_regular := global_widget.font
    font_bold := fonts_map[.UI_Bold]
    line_height := font_regular.line_height
    left_padding := font_regular.xadvance
    results_pen := Vector2{left_padding, line_height}

    results_pen.y -= i32(global_widget.y_offset) * line_height

    for result, index in global_widget.view_results {
        if results_pen.y < line_height {
            results_pen.y += line_height
            continue
        }
        if global_widget.selection == index {
            set_color(.ui_selection_background)
            draw_rect(0, results_pen.y, i32(global_widget.rect.w), line_height, true)
            set_color(.ui_selection_foreground, font_regular.texture)
        } else {
            set_color(.foreground, font_regular.texture)
        }
        results_pen = draw_text(font_regular, results_pen, result.format)
    }

    prompt_query_str := strings.to_string(global_widget.prompt)

    set_color(.ui_border)
    draw_line(0, 0, i32(global_widget.rect.w), 0)
    draw_line(0, line_height, i32(global_widget.rect.w), line_height)

    if global_widget.selection == -1 {
        set_color(.ui_selection_background)
        draw_rect(0, 0, i32(len(prompt_ask_str)) * font_bold.xadvance, line_height, true)
        set_color(.ui_selection_foreground, font_bold.texture)
    } else {
        set_color(.highlight, font_bold.texture)
    }

    set_color(.foreground, font_regular.texture)
    prompt_ask_pen := draw_text(font_bold, {left_padding, 0}, prompt_ask_str)
    draw_text(font_regular, prompt_ask_pen, prompt_query_str)

    cursor_pen := prompt_ask_pen
    cursor_pen.x += prepare_text(font_regular, prompt_query_str[:global_widget.cursor.pos])
    rune_behind_cursor := ' '
    if global_widget.cursor.pos < len(prompt_query_str) {
        rune_behind_cursor = utf8.rune_at(prompt_query_str, global_widget.cursor.pos)
    }
    draw_cursor(font_regular, cursor_pen, rune_behind_cursor, global_widget.cursor_showing, true)


    set_target()
    draw_texture(global_widget.texture, nil, &global_widget.rect)
}

get_find_buffer_format :: proc(buffer: ^Buffer) -> string {
    result := strings.builder_make(context.temp_allocator)
    strings.write_string(&result, buffer.name)
    strings.write_byte(&result, '\n')
    return strings.clone(strings.to_string(result))
}

get_find_file_format :: proc(file: os.File_Info) -> string {
    result := strings.builder_make(context.temp_allocator)
    strings.write_string(&result, file.name)
    if file.is_dir do strings.write_string(&result, "/")
    strings.write_byte(&result, '\n')
    return strings.clone(strings.to_string(result))
}
