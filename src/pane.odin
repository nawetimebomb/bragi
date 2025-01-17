package main

Pane :: struct {
    dimensions : Vector2,
    buffer     : ^Text_Buffer,
}

get_focused_pane :: proc() -> ^Pane {
    return &bragi.panes[bragi.focused_pane]
}

get_buffer_from_current_pane :: proc() -> ^Text_Buffer {
    return get_focused_pane().buffer
}
