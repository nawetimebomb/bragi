package main

import "core:fmt"
import "core:log"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:time"

UI_View_Column_Parse_Proc :: #type proc(d: any) -> string

UI_View_Justify :: enum { left, center, right }

UI_Pane_Action :: enum {
    NONE,
    BUFFERS,
    FILES,
    SEARCH_IN_BUFFER,
}

Pane_State :: struct {
    buffer: ^Buffer,
    caret_coords: Caret_Pos,
}

Result_View_Column :: struct {
    field_name: string,
    justify:    UI_View_Justify,
    length:     int,
    parse_proc: UI_View_Column_Parse_Proc,
}

Result_Buffer :: ^Buffer

Result_Value :: union {
    Result_Buffer,
}

Result :: struct {
    highlight: Caret_Pos,
    value: Result_Value,
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
    target:          ^Pane,
    real_size:       [2]i32,
    relative_size:   [2]i32,
    viewport:        [2]i32,
}

ui_pane_init :: proc() {
    p := &bragi.ui_pane

    p.query = strings.builder_make()
    p.view_columns = make([dynamic]Result_View_Column, 0)
    p.results = make([dynamic]Result, 0)
}

ui_pane_destroy :: proc() {
    p := &bragi.ui_pane

    strings.builder_destroy(&p.query)
    delete(p.view_columns)
    delete(p.results)
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

    switch p.action {
    case .NONE:
    case .BUFFERS:
        item := p.results[p.caret.coords.y]

        if item.value != nil {
            p.target.buffer = item.value.(Result_Buffer)
        }

        sync_caret_coords(p.target)
    case .FILES:
    case .SEARCH_IN_BUFFER:
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
            mms := as_major_mode_name(b.major_mode)
            name_len = len(b.name) if len(b.name) > name_len else name_len
            major_mode_len = len(mms) if len(mms) > major_mode_len else major_mode_len
        }

        append(&p.view_columns,
               Result_View_Column{
                   field_name = "name",
                   justify    = .left,
                   length     = name_len,
                   parse_proc = as_string,
               },
               Result_View_Column{
                   field_name = "status",
                   justify    = .center,
                   length     = STATUS_LEN,
                   parse_proc = as_string,
               },
               Result_View_Column{
                   field_name = "str",
                   justify    = .left,
                   length     = BUF_LENGTH_LEN,
                   parse_proc = as_size_length,
               },
               Result_View_Column{
                   field_name = "major_mode",
                   justify    = .left,
                   length     = major_mode_len + MAJOR_MODE_PADDING,
                   parse_proc = as_major_mode_name,
               },
               Result_View_Column{
                   field_name = "filepath",
                   parse_proc = as_string,
               })
    case .FILES:
    case .SEARCH_IN_BUFFER:
    }
}

rollback_to_prev_value :: proc() {
    p := &bragi.ui_pane

    switch p.action {
    case .NONE:
    case .BUFFERS:
        p.target.buffer = p.prev_state.buffer
    case .FILES:
    case .SEARCH_IN_BUFFER:
    }
}

show_ui_pane :: proc(target: ^Pane, action: UI_Pane_Action) {
    p := &bragi.ui_pane
    p.action = action
    p.caret.coords = {}
    p.enabled = true
    p.target = target
    p.prev_state = {
        buffer = target.buffer,
        caret_coords = target.caret.coords,
    }

    ui_filter_results()
    create_view_columns()
    resize_panes()
}

hide_ui_pane :: proc() {
    p := &bragi.ui_pane

    if !p.did_select {
        rollback_to_prev_value()
    }

    p.action = .NONE
    p.caret.coords = {}
    p.did_select = false
    p.enabled = false
    p.prev_state = {}
    p.target = nil

    strings.builder_reset(&p.query)
    clear(&p.view_columns)
    clear(&p.results)
    resize_panes()
}

ui_filter_results :: proc() {
    p := &bragi.ui_pane
    query := strings.to_string(p.query)
    query_has_value := len(query) > 0

    clear(&p.results)

    switch p.action {
    case .NONE:
    case .BUFFERS:
        for &b, index in bragi.buffers {
            if query_has_value {
                found := strings.contains(b.name, query)
                if !found { continue }
            }

            start := strings.index(b.name, query)
            end := start + len(query)

            result := Result{
                highlight = { start, end },
                value = &b,
            }

            append(&p.results, result)
        }

        if query_has_value {
            append(&p.results, Result{})
        }
    case .FILES:
    case .SEARCH_IN_BUFFER:
    }

    p.caret.coords.y = clamp(p.caret.coords.y, 0, len(p.results) - 1)
}

ui_do_command :: proc(cmd: Command, p: ^Pane, data: any) {
    p := &bragi.ui_pane
    p.caret.last_keystroke = time.tick_now()

    #partial switch cmd {
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

    switch p.action {
    case .NONE:
    case .BUFFERS:
        // NOTE: We only care about the selection with nil pointer because the other ones
        // are changed on the fly, but this one requires a new buffer to be created.
        item := p.results[p.caret.coords.y]

        if item.value == nil {
            p.target.buffer = add(buffer_init(strings.to_string(p.query), 0))
        }

        hide_ui_pane()
    case .FILES:
    case .SEARCH_IN_BUFFER:
    }

    hide_ui_pane()
}

ui_self_insert :: proc(s: string) {
    p := &bragi.ui_pane

    if ok, _ := inject_at(&p.query.buf, p.caret.coords.x, s); ok {
        p.caret.coords.x += len(s)
    }

    ui_filter_results()
}

ui_get_invalid_result_string :: proc() -> string {
    p := &bragi.ui_pane
    tmp := strings.builder_make(context.temp_allocator)

    switch p.action {
    case .NONE:
    case .BUFFERS:
        strings.write_string(&tmp, "Create a buffer with name ")
        strings.write_quoted_string(&tmp, strings.to_string(p.query))
    case .FILES:
    case .SEARCH_IN_BUFFER:
    }

    return strings.to_string(tmp)
}

ui_get_valid_result_string :: proc(result: Result_Value) -> string {
    p := &bragi.ui_pane
    tmp := strings.builder_make(context.temp_allocator)

    switch p.action {
    case .NONE:
    case .BUFFERS:
        b := result.(Result_Buffer)

        for col in p.view_columns {
            v := reflect.struct_field_value_by_name(b^, col.field_name)
            s := col.parse_proc(v)

            if col.length > 0 {
                switch col.justify {
                case .left:
                    s = strings.left_justify(s, col.length, " ", context.temp_allocator)
                case .center:
                    s = strings.center_justify(s, col.length, " ", context.temp_allocator)
                case .right:
                    s = strings.right_justify(s, col.length, " ", context.temp_allocator)
                }
            }

            strings.write_string(&tmp, s)
        }
    case .FILES:
    case .SEARCH_IN_BUFFER:

    }

    return strings.to_string(tmp)
}
