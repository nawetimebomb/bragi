package main


// The settings fat struct
Settings :: struct {
    global_wrap_lines: bool,
}

// NOTE(nawe) the local settings apply to the current active pane
Local_Settings :: struct {
    wrap_lines: bool,
}
