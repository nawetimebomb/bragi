package main

Bottom_Pane_Variant :: union {
    Bottom_Pane_None,
    Bottom_Pane_Buffers,
    Bottom_Pane_Search,
    Bottom_Pane_Files,
}

Bottom_Pane_None :: struct {}
Bottom_Pane_Buffers :: struct {

}
Bottom_Pane_Search :: struct {}
Bottom_Pane_Files :: struct {}

Bottom_Pane :: struct {
    caret:          Caret,
    enabled:        bool,
    input_buffer:   ^Buffer,
    result_buffer:  ^Buffer,
    selected_index: int,
    target_pane:    ^Pane,
    variant:        Bottom_Pane_Variant,
}

bottom_pane_init :: proc() {
    bp := &bragi.bottom_pane

    input := add(buffer_init("__bragi_input__", 15))
    input.enable_history = false

    result := add(buffer_init("__bragi_result__", 32))
    result.enable_history = false

    bp.input_buffer = input
    bp.result_buffer = result
}

bottom_pane_begin :: proc() {
    bp := &bragi.bottom_pane

    if !bp.enabled { return }

    buffer_begin(bp.input_buffer)
    buffer_begin(bp.result_buffer)

    switch v in bp.variant {
    case Bottom_Pane_None:
    case Bottom_Pane_Buffers:
    case Bottom_Pane_Search:
    case Bottom_Pane_Files:
    }
}

bottom_pane_end :: proc() {
    bp := &bragi.bottom_pane

    if !bp.enabled { return }

    buffer_end(bp.input_buffer)
    buffer_end(bp.result_buffer)
}

show_bottom_pane :: proc(target: ^Pane, type: enum { BUFFERS, FILES }) {
    bp := &bragi.bottom_pane
    bp.target_pane = target
    bp.enabled = true
    resize_panes()
}

hide_bottom_pane :: proc() {
    bp := &bragi.bottom_pane
    bp.target_pane = nil
    bp.enabled = false
    resize_panes()
}
