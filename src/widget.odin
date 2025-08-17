package main

import "core:log"
import "core:slice"
import "core:strings"

WIDGET_HEIGHT :: 200

Widget :: struct {
    active:    bool,
    cursor:    Cursor,
    // the selected line or -1 if selecting the prompt
    selection: int,

    contents:  strings.Builder,
    prompt:    strings.Builder,
    variant:   Widget_Variant,

    texture:   ^Texture,
    rect:      Rect,
}

Widget_Variant :: union {
    Widget_Find_Buffer,
}

Widget_Find_Buffer :: struct {
    items: []^Buffer,
}

widget_init :: proc() {
    update_widget_texture()
}

update_widget_texture :: proc() {
    texture_destroy(global_widget.texture)
    global_widget.rect = make_rect(0, window_height - WIDGET_HEIGHT, window_width, WIDGET_HEIGHT)
    global_widget.texture = texture_create(.TARGET, i32(global_widget.rect.w), i32(global_widget.rect.h))
}

widget_open_find_buffer :: proc() {
    widget_open()

    buffers_list := make([dynamic]^Buffer, context.temp_allocator)

    for buffer in open_buffers {
        if active_pane.buffer == buffer do continue
        append(&buffers_list, buffer)
    }
    append(&buffers_list, active_pane.buffer)

    global_widget.variant = Widget_Find_Buffer{
        items = slice.clone(buffers_list[:]),
    }
}

// NOTE(nawe) a generic procedure to make sure we clean up opened
// widget (if any) and set the defaults again
@(private="file")
widget_open :: proc() {
    if global_widget.active do widget_close()

    global_widget.cursor.pos = 0
    global_widget.cursor.sel = 0
    global_widget.selection = -1
    global_widget.active = true
    // update_all_pane_textures()
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
        case .K_ENTER: {
            // handle selection
            unimplemented()
        }
        case .K_BACKSPACE: {
            start := max(global_widget.cursor.pos - 1, 0)
            end := global_widget.cursor.pos
            remove_range(&global_widget.prompt.buf, start, end)
            global_widget.cursor.pos = start
            log.debug(strings.to_string(global_widget.prompt))
            return true
        }
        case .K_DELETE: {
            start := global_widget.cursor.pos
            end := min(global_widget.cursor.pos + 1, len(global_widget.prompt.buf))
            remove_range(&global_widget.prompt.buf, start, end)
            log.debug(strings.to_string(global_widget.prompt))
            return true
        }
    }

    switch v in global_widget.variant {
    case Widget_Find_Buffer: handled = find_buffer_keyboard_event_handler(event, v)
    }

    return
}

find_buffer_keyboard_event_handler :: proc(event: Event_Keyboard, data: Widget_Find_Buffer) -> bool {
    cmd := map_keystroke_to_command(event.key_code, event.modifiers)

    #partial switch cmd {
        case .modifier: return true // handled as a modifier which is valid in this context
    }

    return false
}


update_and_draw_widget :: proc() {
    if !global_widget.active do return

    set_target(global_widget.texture)
    set_color(.foreground)
    prepare_for_drawing()

    switch v in global_widget.variant {
    case Widget_Find_Buffer:

    }

    set_target()
    draw_texture(global_widget.texture, nil, &global_widget.rect)
}
