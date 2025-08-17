package main

import "core:strings"

Widget_Type :: enum {
    find_file,
}

Widget :: struct {
    cursor:    Cursor,
    selection: int,
    contents:  strings.Builder,
    type:      Widget_Type,
}

widget_open :: proc(type: Widget_Type) {
    switch type {
    case .find_file:
        unimplemented()
    }
}

update_and_draw_widget :: proc() {
    if active_widget == nil do return

    switch active_widget.type {
    case .find_file: widget_find_file()
    }
}

widget_find_file :: proc() {

}
