package main

import "core:log"
import "core:slice"
import "core:time"

Bottom_Pane_On_Select_Proc :: #type proc()

Bottom_Pane_Action :: enum {
    NONE,
    BUFFERS,
    FILES,
}

Bottom_Pane_Result :: struct {
    label:     string,
    index:     int,
}

Bottom_Pane :: struct {
    action:          Bottom_Pane_Action,
    caret:           Caret,
    enabled:         bool,
    buffer:          ^Buffer,
    results:         [dynamic]Bottom_Pane_Result,
    selection_index: int,
    target:          ^Pane,
    viewport:        [2]i32,
    real_size:       [2]i32,
    relative_size:   [2]i32,
}

bottom_pane_init :: proc() {
    bp := &bragi.bottom_pane

    bp.buffer = add(buffer_init("__bragi_input__", 0))
    bp.buffer.enable_history = false
    bp.buffer.internal = true

    bp.results = make([dynamic]Bottom_Pane_Result, 0)
    bp.selection_index = 0
}

bottom_pane_destroy :: proc() {
    bp := &bragi.bottom_pane

    bp.buffer = nil
    delete(bp.results)
}

bottom_pane_begin :: proc() {
    bp := &bragi.bottom_pane
    caret := &bp.caret

    if !bp.enabled { return }

    buffer_begin(bp.buffer)

    if should_caret_blink(caret) {
        caret.last_update = time.tick_now()
        caret.blinking = !caret.blinking
        caret.blinking_count += 1
    }

    switch bp.action {
    case .NONE:
    case .BUFFERS:
        current_sel := bp.results[bp.selection_index]
        bp.target.buffer = &bragi.buffers[current_sel.index]
        sync_caret_coords(bp.target)
    case .FILES:
    }
}

bottom_pane_end :: proc() {
    bp := &bragi.bottom_pane

    if !bp.enabled { return }

    buffer_end(bp.buffer)
}

show_bottom_pane :: proc(target: ^Pane, action: Bottom_Pane_Action) {
    bp := &bragi.bottom_pane
    bp.action = action
    bp.target = target
    bp.enabled = true

    switch action {
    case .NONE:
        log.error("NONE is not a valid type of bottom pane")
    case .BUFFERS:
        for &b, index in bragi.buffers {
            if !b.internal {
                append(&bp.results, Bottom_Pane_Result{
                    label = b.name,
                    index = index,
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
    bp.selection_index = 0
    buffer_reset(bp.buffer)
    clear(&bp.results)
    resize_panes()
}

ui_do_command :: proc(cmd: Command, p: ^Pane, data: any) {
    #partial switch cmd {
        case .next_line:      ui_move_selection(.DOWN)
        case .previous_line:  ui_move_selection(.UP)
        case .ui_select:      ui_select()
        case .self_insert:    ui_self_insert(data.(string))
    }
}

ui_move_selection :: proc(t: Caret_Translation) {
    bp := &bragi.bottom_pane

    #partial switch t {
        case .DOWN: {
            bp.selection_index += 1
            if bp.selection_index >= len(bp.results) {
                bp.selection_index = 0
            }
        }
        case .UP: {
            bp.selection_index -= 1
            if bp.selection_index < 0 {
                bp.selection_index = len(bp.results) - 1
            }
        }
    }
}

ui_select :: proc() {
    bp := &bragi.bottom_pane

    switch bp.action {
    case .NONE:
    case .BUFFERS:
        v := bp.results[bp.selection_index]
        bp.target.buffer = &bragi.buffers[v.index]
    case .FILES:
    }

    hide_bottom_pane()
}

ui_self_insert :: proc(s: string) {
    bp := &bragi.bottom_pane
    cursor := caret_to_buffer_cursor(bp.buffer, bp.caret.coords)
    bp.caret.coords.x += insert(bp.buffer, cursor, s)
}
