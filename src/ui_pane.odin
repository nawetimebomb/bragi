package main

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import "core:time"

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

Result_Buffer :: struct {
    buffer: ^Buffer,
}

Result_File :: struct {}

Result_Value :: union {
    Result_Buffer,
    Result_File,
}

UI_Pane_Result :: struct {
    label: string,
    value: Result_Value,
}

UI_Pane :: struct {
    action:          UI_Pane_Action,
    caret:           Caret,
    enabled:         bool,
    did_select:      bool,
    prev_state:      Pane_State,
    temp_value:      strings.Builder,
    query:           strings.Builder,
    results:         [dynamic]UI_Pane_Result,
    target:          ^Pane,
    viewport:        [2]i32,
    real_size:       [2]i32,
    relative_size:   [2]i32,
}

ui_pane_init :: proc() {
    bp := &bragi.ui_pane

    bp.query = strings.builder_make()
    bp.temp_value = strings.builder_make()
    bp.results = make([dynamic]UI_Pane_Result, 0)
}

ui_pane_destroy :: proc() {
    bp := &bragi.ui_pane

    strings.builder_destroy(&bp.query)
    strings.builder_destroy(&bp.temp_value)
    delete(bp.results)
}

ui_pane_begin :: proc() {
    bp := &bragi.ui_pane
    caret := &bp.caret

    if !bp.enabled { return }

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

    switch bp.action {
    case .NONE:
    case .BUFFERS:
        current_sel := bp.results[bp.caret.coords.y]
        b := current_sel.value.(Result_Buffer).buffer

        if b != nil {
            bp.target.buffer = b
        }

        sync_caret_coords(bp.target)
    case .FILES:
    case .SEARCH_IN_BUFFER:
    }
}

ui_pane_end :: proc() {
    bp := &bragi.ui_pane

    if !bp.enabled { return }
}

rollback_to_prev_value :: proc() {
    bp := &bragi.ui_pane

    switch bp.action {
    case .NONE:
    case .BUFFERS:
        bp.target.buffer = bp.prev_state.buffer
    case .FILES:
    case .SEARCH_IN_BUFFER:
    }
}

show_ui_pane :: proc(target: ^Pane, action: UI_Pane_Action) {
    bp := &bragi.ui_pane
    bp.action = action
    bp.caret.coords = {}
    bp.enabled = true
    bp.target = target

    switch action {
    case .NONE:
    case .BUFFERS:
        bp.prev_state.buffer = target.buffer
    case .FILES:
    case .SEARCH_IN_BUFFER:
    }

    ui_filter_results()
    resize_panes()
}

hide_ui_pane :: proc() {
    bp := &bragi.ui_pane

    if !bp.did_select {
        rollback_to_prev_value()
    }

    bp.action = .NONE
    bp.caret.coords = {}
    bp.did_select = false
    bp.enabled = false
    bp.target = nil

    strings.builder_reset(&bp.query)
    strings.builder_reset(&bp.temp_value)
    clear(&bp.results)
    resize_panes()
}

ui_filter_results :: proc() {
    bp := &bragi.ui_pane
    query := strings.to_string(bp.query)
    query_has_value := len(query) > 0

    clear(&bp.results)
    strings.builder_reset(&bp.temp_value)

    switch bp.action {
    case .NONE:
    case .BUFFERS:
        for &b, index in bragi.buffers {
            if query_has_value {
                if !strings.contains(b.name, query) { continue }
            }

            append(&bp.results, UI_Pane_Result{
                label = b.name,
                value = Result_Buffer{ buffer = &b },
            })
        }

        if query_has_value {
            strings.write_string(&bp.temp_value, "Create buffer with name ")
            strings.write_quoted_string(&bp.temp_value, query)
            append(&bp.results, UI_Pane_Result{
                label = strings.to_string(bp.temp_value),
                value = Result_Buffer{ buffer = nil },
            })
        }
    case .FILES:
    case .SEARCH_IN_BUFFER:
    }

    bp.caret.coords.y = clamp(bp.caret.coords.y, 0, len(bp.results) - 1)
}

ui_do_command :: proc(cmd: Command, p: ^Pane, data: any) {
    bp := &bragi.ui_pane
    bp.caret.last_keystroke = time.tick_now()

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
    bp := &bragi.ui_pane
    pos = bp.caret.coords
    query := strings.to_string(bp.query)
    results := bp.results

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
    bp := &bragi.ui_pane
    new_pos := ui_translate(t)
    start := min(bp.caret.coords.x, new_pos.x)
    end := max(bp.caret.coords.x, new_pos.x)
    remove_range(&bp.query.buf, start, end)
    bp.caret.coords.x = start
    ui_filter_results()
}

ui_move_to :: proc(t: Caret_Translation) {
    bp := &bragi.ui_pane
    bp.caret.coords = ui_translate(t)
}

ui_select :: proc() {
    bp := &bragi.ui_pane
    bp.did_select = true

    switch bp.action {
    case .NONE:
    case .BUFFERS:
        // NOTE: We only care about the selection with nil pointer because the other ones are
        // changed on the fly, but this one requires a new buffer to be created.
        current_sel := bp.results[bp.caret.coords.y]
        b := current_sel.value.(Result_Buffer).buffer

        if b == nil {
            bp.target.buffer = add(buffer_init(strings.to_string(bp.query), 0))
        }

        hide_ui_pane()
    case .FILES:
    case .SEARCH_IN_BUFFER:
    }

    hide_ui_pane()
}

ui_self_insert :: proc(s: string) {
    bp := &bragi.ui_pane

    if ok, _ := inject_at(&bp.query.buf, bp.caret.coords.x, s); ok {
        bp.caret.coords.x += len(s)
    }

    ui_filter_results()
}
