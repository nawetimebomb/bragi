package main

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

WIDGET_HEIGHT_IN_ROWS :: 15

Widget :: struct {
    active:              bool,
    cursor:              Cursor,
    cursor_showing:      bool,
    cursor_blink_timer:  time.Tick,

    // the selected line or -1 if selecting the prompt
    selection:           int,
    results_last_index:  int,
    // all_results:         [dynamic]Result, // the one to keep
    // view_results:        []Result, // the one to show, contains the filters

    contents:            strings.Builder,
    prompt:              strings.Builder,
    variant:             Widget_Variant,

    font:                ^Font,
    texture:             ^Texture,
    rect:                Rect,
    y_offset:            int,
}

Widget_Variant :: union {
    Widget_Find_Buffer,
}

Widget_Find_Buffer :: struct {
    items: []^Buffer,
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

    buffers_list := make([dynamic]^Buffer, context.temp_allocator)

    for buffer in open_buffers {
        if active_pane.buffer == buffer do continue
        append(&buffers_list, buffer)
    }

    // prefer most recent edited buffers... (not stable sorting but mostly cosmetic, not really important)
    slice.sort_by(buffers_list[:], proc(a: ^Buffer, b: ^Buffer) -> bool {
        current_tick := time.tick_now()
        return time.tick_diff(a.last_edit_time, current_tick) < time.tick_diff(b.last_edit_time, current_tick)
    })

    // ...but append the current active buffer last
    append(&buffers_list, active_pane.buffer)

    global_widget.variant = Widget_Find_Buffer{
        items  = slice.clone(buffers_list[:]),
    }
    global_widget.results_last_index = len(buffers_list) - 1
}

// NOTE(nawe) a generic procedure to make sure we clean up opened
// widget (if any) and set the defaults again
@(private="file")
widget_open :: proc() {
    if global_widget.active do widget_close()

    global_widget.results_last_index = -1
    global_widget.cursor.pos = 0
    global_widget.cursor.sel = 0
    global_widget.selection = -1
    global_widget.active = true
    flag_pane(active_pane, {.Need_Full_Repaint})
}

widget_close :: proc() {
    if !global_widget.active do return
    global_widget.active = false

    switch v in global_widget.variant {
    case Widget_Find_Buffer:
        delete(v.items)
    }

    strings.builder_destroy(&global_widget.contents)
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
                global_widget.selection = global_widget.results_last_index
            }

            return true
        }
        case .move_down: {
            global_widget.selection += 1

            if global_widget.selection > global_widget.results_last_index {
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

    switch v in global_widget.variant {
    case Widget_Find_Buffer: handled = find_buffer_keyboard_event_handler(event, v)
    }

    return
}

find_buffer_keyboard_event_handler :: proc(event: Event_Keyboard, data: Widget_Find_Buffer) -> bool {
    #partial switch event.key_code {
        case .K_ENTER: {
            if global_widget.selection > -1 {
                buffer := data.items[global_widget.selection]
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

update_and_draw_widget :: proc() {
    if !global_widget.active do return
    assert(global_widget.results_last_index != -1)

    if time.tick_diff(last_keystroke, time.tick_now()) < CURSOR_RESET_TIMEOUT {
        global_widget.cursor_showing = true
        global_widget.cursor_blink_timer = time.tick_now()
    }

    if time.tick_diff(global_widget.cursor_blink_timer, time.tick_now()) > CURSOR_BLINK_TIMEOUT {
        global_widget.cursor_showing = !global_widget.cursor_showing
        global_widget.cursor_blink_timer = time.tick_now()
    }

    switch v in global_widget.variant {
    case Widget_Find_Buffer:
        if global_widget.selection > -1 {
            buffer := v.items[global_widget.selection]

            if active_pane.buffer != buffer {
                switch_to_buffer(active_pane, buffer)
            }
        }
    }

    set_target(global_widget.texture)
    set_color(.background)
    prepare_for_drawing()

    prompt_ask_str: string
    font_regular := global_widget.font
    font_bold := fonts_map[.UI_Bold]
    line_height := font_regular.line_height
    left_padding := font_regular.xadvance
    results_pen := Vector2{left_padding, line_height}

    switch v in global_widget.variant {
    case Widget_Find_Buffer:
        prompt_ask_str = fmt.tprintf(
            "{}/{}  Switch to: ",
            global_widget.selection + 1,
            len(v.items),
        )

        for item, index in v.items {
            if global_widget.selection == index {
                set_color(.ui_selection_background)
                draw_rect(0, results_pen.y, i32(global_widget.rect.w), line_height, true)
                set_color(.ui_selection_foreground, font_regular.texture)
            } else {
                set_color(.foreground, font_regular.texture)
            }
            results_pen = draw_text(font_regular, results_pen, fmt.tprintf("{}\n", item.name))
        }
    }

    prompt_query_str := strings.to_string(global_widget.prompt)

    set_color(.ui_border)
    draw_line(0, 0, i32(global_widget.rect.w), 0)
    draw_line(0, line_height, i32(global_widget.rect.w), line_height)

    if global_widget.selection == -1 {
        set_color(.ui_selection_background)
        draw_rect(0, 0, i32(len(prompt_ask_str)) * left_padding, line_height, true)
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
