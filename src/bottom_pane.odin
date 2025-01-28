package main

import "core:log"
import "core:time"

Bottom_Pane_On_Select_Proc :: #type proc()

Bottom_Pane_Action :: enum {
    NONE,
    BUFFERS,
    FILES,
}

Bottom_Pane_Result :: struct {
    label:     string,
    on_select: Bottom_Pane_On_Select_Proc,
}

Bottom_Pane :: struct {
    action:         Bottom_Pane_Action,
    caret:          Caret,
    enabled:        bool,
    buffer:   ^Buffer,
    results:        [dynamic]Bottom_Pane_Result,
    selected_index: int,
    target_pane:    ^Pane,
    viewport:       [2]i32,
    real_size:      [2]i32,
    relative_size:  [2]i32,
}

bottom_pane_init :: proc() {
    bp := &bragi.bottom_pane

    bp.buffer = add(buffer_init("__bragi_input__", 0))
    bp.buffer.enable_history = false
    bp.buffer.internal = true

    bp.results = make([dynamic]Bottom_Pane_Result, 0)
    bp.selected_index = 0
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
}

bottom_pane_end :: proc() {
    bp := &bragi.bottom_pane

    if !bp.enabled { return }

    buffer_end(bp.buffer)
}

show_bottom_pane :: proc(target: ^Pane, action: Bottom_Pane_Action) {
    bp := &bragi.bottom_pane
    bp.action = action
    bp.target_pane = target
    bp.enabled = true

    switch action {
    case .NONE:
        log.error("NONE is not a valid type of bottom pane")
    case .BUFFERS:
        for &b in bragi.buffers {
            if !b.internal {
                append(&bp.results, Bottom_Pane_Result{
                    label = b.name,
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
    bp.target_pane = nil
    bp.enabled = false
    bp.selected_index = 0
    buffer_reset(bp.buffer)
    clear(&bp.results)
    resize_panes()
}
