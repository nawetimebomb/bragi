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
    ui_modeline_active_background,
    ui_modeline_active_foreground,
    ui_modeline_active_highlight,
    ui_modeline_inactive_background,
    ui_modeline_inactive_foreground,
    ui_modeline_inactive_highlight,

    debug_background,
    debug_foreground,
}

Tab_Character :: enum {
    space, tab,
}

Modeline_Position :: enum {
    bottom, top,
}

// The settings fat struct
Settings :: struct {
    editor_font_size: int,
    ui_font_size:     int,

    always_wrap_lines:        bool,

    cursor_is_a_block:        bool,
    cursor_width:             int,

    default_tab_size:         int,
    default_tab_character:    Tab_Character,

    show_line_numbers:        bool,
    maximize_window_on_start: bool,
    modeline_position:        Modeline_Position,

    moving_while_pressing_shift_does_select: bool,
}

settings_init :: proc() {
    DEFAULT_FONT_EDITOR_SIZE :: 24
    DEFAULT_FONT_UI_SIZE     :: 20

    settings.editor_font_size = DEFAULT_FONT_EDITOR_SIZE
    settings.ui_font_size     = DEFAULT_FONT_UI_SIZE

    settings.cursor_is_a_block = true
    settings.cursor_width = 2
    settings.show_line_numbers = true
    settings.modeline_position = .bottom

    settings.moving_while_pressing_shift_does_select = true

    colorscheme[.background]                        = hex_to_color(0x050505)
    colorscheme[.foreground]                        = hex_to_color(0xa08563)
    colorscheme[.cursor_active]                     = hex_to_color(0xcd950c)
    colorscheme[.cursor_passive]                    = hex_to_color(0x98a098)
    colorscheme[.cursor_all]                        = hex_to_color(0x6b8e23)

    colorscheme[.region]                            = hex_to_color(0x0a0b62)

    colorscheme[.ui_border]                         = hex_to_color(0x373b41)
    colorscheme[.ui_fringe]                         = hex_to_color(0x050505)
    colorscheme[.ui_line_number_background]         = hex_to_color(0x050505)
    colorscheme[.ui_line_number_foreground]         = hex_to_color(0x373b41)
    colorscheme[.ui_line_number_current_background] = hex_to_color(0x131313)
    colorscheme[.ui_line_number_current_foreground] = hex_to_color(0x98a098)
    colorscheme[.ui_modeline_active_background]     = hex_to_color(0x131313)
    colorscheme[.ui_modeline_active_foreground]     = hex_to_color(0xa08563)
    colorscheme[.ui_modeline_active_highlight]      = hex_to_color(0xcd950c)

    colorscheme[.ui_modeline_inactive_background]   = hex_to_color(0x010101)
    colorscheme[.ui_modeline_inactive_foreground]   = hex_to_color(0x616161)
    colorscheme[.ui_modeline_inactive_highlight]    = hex_to_color(0x616161)

    colorscheme[.debug_background] = {16, 16, 16, 150}
    colorscheme[.debug_foreground] = {255, 255, 255, 255}
}

hex_to_color :: proc(hex: int) -> (result: Color) {
    result.r = u8((hex >> 16) & 0xff)
    result.g = u8((hex >> 8) & 0xff)
    result.b = u8((hex) & 0xff)
    result.a = 255
    return
}
