package main

Tab_Character :: enum {
    space, tab,
}

// The settings fat struct
Settings :: struct {
    always_wrap_lines:        bool,

    cursor_is_a_block:        bool,
    cursor_width:             int,

    default_tab_size:         int,
    default_tab_character:    Tab_Character,

    show_line_numbers:        bool,
    maximize_window_on_start: bool,
}

settings_init :: proc() {
    settings.cursor_is_a_block = true
    settings.cursor_width = 2
    settings.show_line_numbers = true
}
