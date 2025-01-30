package main

import "core:log"
import "core:slice"
import "core:strings"
import "core:time"

Bottom_Pane_Action :: enum {
    NONE,
    BUFFERS,
    FILES,
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

Bottom_Pane :: struct {
    action:          Bottom_Pane_Action,
    caret:           Caret,
    enabled:         bool,
    query:           strings.Builder,
    results:         [dynamic]UI_Pane_Result,
    target:          ^Pane,
    viewport:        [2]i32,
    real_size:       [2]i32,
    relative_size:   [2]i32,
}

bottom_pane_init :: proc() {
    bp := &bragi.bottom_pane

    bp.query = strings.builder_make()
    bp.results = make([dynamic]UI_Pane_Result, 0)
}

bottom_pane_destroy :: proc() {
    bp := &bragi.bottom_pane

    delete(bp.results)
    strings.builder_destroy(&bp.query)
}

bottom_pane_begin :: proc() {
    bp := &bragi.bottom_pane
    caret := &bp.caret

    if !bp.enabled { return }

    if should_caret_blink(caret) {
        caret.last_update = time.tick_now()
        caret.blinking = !caret.blinking
        caret.blinking_count += 1
    }

    switch bp.action {
    case .NONE:
    case .BUFFERS:
        current_sel := bp.results[bp.caret.coords.y]
        b := current_sel.value.(Result_Buffer).buffer
        bp.target.buffer = b
        sync_caret_coords(bp.target)
    case .FILES:
    }
}

bottom_pane_end :: proc() {
    bp := &bragi.bottom_pane

    if !bp.enabled { return }
}

show_bottom_pane :: proc(target: ^Pane, action: Bottom_Pane_Action) {
    bp := &bragi.bottom_pane
    bp.action = action
    bp.target = target
    bp.enabled = true
    bp.caret.coords = {}

    switch action {
    case .NONE:
        log.error("NONE is not a valid type of bottom pane")
    case .BUFFERS:
        for &b, index in bragi.buffers {
            if !b.internal {
                append(&bp.results, UI_Pane_Result{
                    label = b.name,
                    value = Result_Buffer{ buffer = &b },
                })
            }
        }

    case .FILES:
    }

    resize_panes()
}

hide_bottom_pane :: proc() {
    bp := &bragi.bottom_pane
    bp.action = .NONE
    bp.target = nil
    bp.enabled = false
    bp.caret.coords = {}
    strings.builder_reset(&bp.query)
    clear(&bp.results)
    resize_panes()
}

ui_do_command :: proc(cmd: Command, p: ^Pane, data: any) {
    #partial switch cmd {
        case .ui_select:            ui_select()

        case .delete_backward_char: ui_delete_to(.LEFT)
        case .delete_forward_char:  ui_delete_to(.RIGHT)

        case .beginning_of_line:    ui_move_to(.LINE_START)
        case .beginning_of_buffer:  ui_move_to(.LINE_START)
        case .end_of_line:          ui_move_to(.LINE_END)
        case .end_of_buffer:        ui_move_to(.LINE_END)

        case .backward_char:        ui_move_to(.LEFT)
        case .forward_char:         ui_move_to(.RIGHT)
        case .next_line:            ui_move_to(.DOWN)
        case .previous_line:        ui_move_to(.UP)

        case .self_insert:          ui_self_insert(data.(string))
    }
}

ui_translate :: proc(t: Caret_Translation) -> (pos: Caret_Pos) {
    bp := &bragi.bottom_pane
    pos = bp.caret.coords
    query := strings.to_string(bp.query)
    results := bp.results

    #partial switch t {
        case .DOWN: {
            pos.y += 1
            if pos.y >= len(results) {
                pos.y = 0
            }
        }
        case .UP: {
            pos.y -= 1
            if pos.y < 0 {
                pos.y = len(results) - 1
            }
        }
        case .LEFT: {
            if pos.x > 0 {
                pos.x -= 1
            }
        }
        case .RIGHT: {
            if pos.x < len(query) {
                pos.x += 1
            }
        }
        case .LINE_START: {
            pos.x = 0
        }
        case .LINE_END: {
            pos.x = len(query)
        }
    }

    return
}

ui_delete_to :: proc(t: Caret_Translation) {
    bp := &bragi.bottom_pane
    new_pos := ui_translate(t)
    start := min(bp.caret.coords.x, new_pos.x)
    end := max(bp.caret.coords.x, new_pos.x)
    remove_range(&bp.query.buf, start, end)
    bp.caret.coords.x = start
}

ui_move_to :: proc(t: Caret_Translation) {
    bp := &bragi.bottom_pane
    bp.caret.coords = ui_translate(t)
}

ui_select :: proc() {
    bp := &bragi.bottom_pane

    switch bp.action {
    case .NONE:
    case .BUFFERS:
        // NOTE: Buffer in pane changes as the user navigate through the open buffers,
        // so just closing this should work.
        hide_bottom_pane()
    case .FILES:
    }

    hide_bottom_pane()
}

ui_self_insert :: proc(s: string) {
    bp := &bragi.bottom_pane

    if ok, _ := inject_at(&bp.query.buf, bp.caret.coords.x, s); ok {
        bp.caret.coords.x += len(s)
    }
}
