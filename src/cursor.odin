package main

CURSOR_BLINK_TIMER :: 1000 / FPS * 60

Cursor :: struct {
    animated       : bool,
    hidden         : bool,
    timer          : u32,
    position       : Vector2,
    previous_x     : int,
    region_enabled : bool,
    region_start   : Vector2,
    selection_mode : bool,
}

cursor_canonicalize :: proc(window_pos: Vector2) -> Vector2 {
    buf := bragi.cbuffer
    std_char_size := get_standard_character_size()

    return {
        buf.viewport.x + window_pos.x / std_char_size.x,
        buf.viewport.y + window_pos.y / std_char_size.y,
    }
}
