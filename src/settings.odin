package main

Color :: distinct [4]u8

Face_Color :: enum {
    background,
    foreground,
    cursor_active,
    cursor_passive,
    cursor_all,
    highlight,
    region,

    ui_border,
    ui_fringe,
    ui_line_number_background,
    ui_line_number_foreground,
    ui_line_number_current_background,
    ui_line_number_current_foreground,
}

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

    moving_while_pressing_shift_does_select: bool,
}

settings_init :: proc() {
    settings.cursor_is_a_block = true
    settings.cursor_width = 2
    settings.show_line_numbers = true

    settings.moving_while_pressing_shift_does_select = true

    colorscheme[.background]                        = hex_to_color(0x050505)
    colorscheme[.foreground]                        = hex_to_color(0xa08563)
    colorscheme[.cursor_active]                     = hex_to_color(0xcd950c)
    colorscheme[.cursor_passive]                    = hex_to_color(0x98a098)
    colorscheme[.cursor_all]                        = hex_to_color(0x6b8e23)

    colorscheme[.ui_border]                         = hex_to_color(0x373b41)
    colorscheme[.ui_fringe]                         = hex_to_color(0x050505)
    colorscheme[.ui_line_number_background]         = hex_to_color(0x050505)
    colorscheme[.ui_line_number_foreground]         = hex_to_color(0x373b41)
    colorscheme[.ui_line_number_current_background] = hex_to_color(0x131313)
    colorscheme[.ui_line_number_current_foreground] = hex_to_color(0x98a098)
}

hex_to_color :: proc(hex: int) -> (result: Color) {
    result.r = u8((hex >> 16) & 0xff)
    result.g = u8((hex >> 8) & 0xff)
    result.b = u8((hex) & 0xff)
    result.a = 255
    return
}
