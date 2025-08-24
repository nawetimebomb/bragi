package main

Color :: distinct [4]u8

Face_Color :: enum u8 {
    undefined = 0, // used internally as default 'noop'

    background,
    foreground,
    cursor_active,
    cursor_inactive,
    highlight,
    region,
    search_background,
    search_foreground,

    code_builtin,
    code_comment,
    code_constant_value,
    code_directive,
    code_enum_variant,
    code_function_name,
    code_keyword,
    code_string,
    code_type,
    code_variable_name,

    ui_border,
    ui_selection_background,
    ui_selection_foreground,
    ui_line_number_background,
    ui_line_number_foreground,
    ui_line_number_background_current,
    ui_line_number_foreground_current,
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

    use_emacs_keybindings: bool,
}

settings_init :: proc() {
    DEFAULT_FONT_EDITOR_SIZE :: 24
    DEFAULT_FONT_UI_SIZE     :: 20

    settings.editor_font_size = DEFAULT_FONT_EDITOR_SIZE
    settings.ui_font_size     = DEFAULT_FONT_UI_SIZE

    settings.default_tab_size      = 4
    settings.default_tab_character = .space

    settings.cursor_is_a_block = true
    settings.cursor_width      = 2
    settings.show_line_numbers = true
    settings.modeline_position = .bottom

    settings.moving_while_pressing_shift_does_select = true

    settings.use_emacs_keybindings = true

    colorscheme[.background]                        = _hex_to_color(0x050505)
    colorscheme[.foreground]                        = _hex_to_color(0xa08563)
    colorscheme[.highlight]                         = _hex_to_color(0xcd950c)
    colorscheme[.cursor_active]                     = _hex_to_color(0xcd950c)
    colorscheme[.cursor_inactive]                   = _hex_to_color(0x98a098)
    colorscheme[.region]                            = _hex_to_color(0x0a0b62)
    colorscheme[.search_background]                 = _hex_to_color(0xd2d2d2)
    colorscheme[.search_foreground]                 = _hex_to_color(0x010101)

    colorscheme[.code_builtin]                      = _hex_to_color(0x875e9a)
    colorscheme[.code_comment]                      = _hex_to_color(0xe27d51)
    colorscheme[.code_constant_value]               = _hex_to_color(0x5aa0b3)
    colorscheme[.code_directive]                    = _hex_to_color(0x875e9a)
    colorscheme[.code_enum_variant]                 = _hex_to_color(0x98a098)
    colorscheme[.code_function_name]                = _hex_to_color(0xa08563)
    colorscheme[.code_keyword]                      = _hex_to_color(0xcd950c)
    colorscheme[.code_string]                       = _hex_to_color(0x6b8e23)
    colorscheme[.code_type]                         = _hex_to_color(0x98a098)
    colorscheme[.code_variable_name]                = _hex_to_color(0xa08563)

    colorscheme[.ui_border]                         = _hex_to_color(0x373b41)
    colorscheme[.ui_selection_background]           = _hex_to_color(0x0a0b62)
    colorscheme[.ui_selection_foreground]           = _hex_to_color(0xd2d2d2)
    colorscheme[.ui_line_number_background]         = _hex_to_color(0x050505)
    colorscheme[.ui_line_number_foreground]         = _hex_to_color(0x373b41)
    colorscheme[.ui_line_number_background_current] = _hex_to_color(0x131313)
    colorscheme[.ui_line_number_foreground_current] = _hex_to_color(0x98a098)
    colorscheme[.ui_modeline_active_background]     = _hex_to_color(0x131313)
    colorscheme[.ui_modeline_active_foreground]     = _hex_to_color(0xa08563)
    colorscheme[.ui_modeline_active_highlight]      = _hex_to_color(0xcd950c)

    colorscheme[.ui_modeline_inactive_background]   = _hex_to_color(0x010101)
    colorscheme[.ui_modeline_inactive_foreground]   = _hex_to_color(0x616161)
    colorscheme[.ui_modeline_inactive_highlight]    = _hex_to_color(0x616161)

    colorscheme[.debug_background] = {16, 16, 16, 150}
    colorscheme[.debug_foreground] = {255, 255, 255, 255}

    _settings_setup_basic_bragi_keybindings()

    if settings.use_emacs_keybindings {
        _settings_setup_emacs_keybindings()
    }
}

// Just the default, basic, keybindings for Bragi
@(private="file")
_settings_setup_basic_bragi_keybindings :: proc() {
    commands_map["Home"]  = .move_start
    commands_map["End"]   = .move_end
    commands_map["Left"]  = .move_left
    commands_map["Right"] = .move_right
    commands_map["Down"]  = .move_down
    commands_map["Up"]    = .move_up

    commands_map["Shift-Left"]  = .select_left
    commands_map["Shift-Right"] = .select_right
    commands_map["Shift-Down"]  = .select_down
    commands_map["Shift-Up"]    = .select_up

    when ODIN_OS == .Darwin {
        commands_map["Cmd-Left"]  = .move_prev_word
        commands_map["Cmd-Right"] = .move_next_word
        commands_map["Cmd-Up"]    = .move_prev_paragraph
        commands_map["Cmd-Down"]  = .move_next_paragraph

        commands_map["Cmd-Shift-Left"]  = .select_prev_word
        commands_map["Cmd-Shift-Right"] = .select_next_word
        commands_map["Cmd-Shift-Up"]    = .select_prev_paragraph
        commands_map["Cmd-Shift-Down"]  = .select_next_paragraph

        commands_map["Cmd-A"] = .select_all
        commands_map["Cmd-+"] = .increase_font_size
        commands_map["Cmd--"] = .decrease_font_size
        commands_map["Cmd-0"] = .reset_font_size
    } else {
        commands_map["Ctrl-Left"]  = .move_prev_word
        commands_map["Ctrl-Right"] = .move_next_word
        commands_map["Ctrl-Up"]    = .move_prev_paragraph
        commands_map["Ctrl-Down"]  = .move_next_paragraph

        commands_map["Ctrl-Shift-Left"]  = .select_prev_word
        commands_map["Ctrl-Shift-Right"] = .select_next_word
        commands_map["Ctrl-Shift-Up"]    = .select_prev_paragraph
        commands_map["Ctrl-Shift-Down"]  = .select_next_paragraph

        commands_map["Ctrl-A"] = .select_all
        commands_map["Ctrl-+"] = .increase_font_size
        commands_map["Ctrl--"] = .decrease_font_size
        commands_map["Ctrl-0"] = .reset_font_size
    }
}

@(private="file")
_settings_setup_emacs_keybindings :: proc() {
    commands_map["Ctrl-X"] = .modifier
    commands_map["Ctrl-G"] = .quit_mode

    commands_map["Ctrl-Space"] = .toggle_selection_mode

    commands_map["Ctrl-X-B"]      = .find_buffer
    commands_map["Ctrl-X-Ctrl-B"] = .find_buffer
    commands_map["Ctrl-X-Ctrl-F"] = .find_file
    commands_map["Ctrl-X-K"]      = .close_current_buffer
    commands_map["Ctrl-X-Ctrl-S"] = .save_buffer
    commands_map["Ctrl-X-Ctrl-W"] = .save_buffer_as

    commands_map["Ctrl-S"] = .search_forward
    commands_map["Ctrl-R"] = .search_backward

    commands_map["Ctrl-X-Ctrl-P"] = .select_all

    commands_map["Alt-<"]  = .move_start
    commands_map["Alt->"]  = .move_end
    commands_map["Ctrl-B"] = .move_left
    commands_map["Ctrl-F"] = .move_right
    commands_map["Ctrl-N"] = .move_down
    commands_map["Ctrl-P"] = .move_up
    commands_map["Alt-B"]  = .move_prev_word
    commands_map["Alt-F"]  = .move_next_word
    commands_map["Alt-{"]  = .move_prev_paragraph
    commands_map["Alt-}"]  = .move_next_paragraph
    commands_map["Alt-V"]  = .move_prev_page
    commands_map["Ctrl-V"] = .move_next_page
    commands_map["Ctrl-A"] = .move_beginning_of_line
    commands_map["Ctrl-E"] = .move_end_of_line

    commands_map["Alt-P"]       = .clone_cursor_up
    commands_map["Alt-N"]       = .clone_cursor_down
    commands_map["Alt-Shift-B"] = .clone_cursor_prev_word
    commands_map["Alt-Shift-F"] = .clone_cursor_next_word

    commands_map["Ctrl-D"] = .remove_right
    commands_map["Ctrl-K"] = .cut_line

    commands_map["Ctrl-X-3"] = .new_pane_to_the_right
    commands_map["Alt-O"]    = .other_pane
    commands_map["Ctrl-X-O"] = .other_pane
    commands_map["Ctrl-X-0"] = .close_this_pane
    commands_map["Ctrl-X-1"] = .close_other_panes

    commands_map["Ctrl-L"]         = .recenter_cursor
    commands_map["Ctrl-LeftTab"]   = .prev_cursor
    commands_map["Ctrl-Tab"]       = .next_cursor
    commands_map["Ctrl-Shift-A"]   = .all_cursors

    commands_map["Ctrl-/"] = .undo
    commands_map["Ctrl-?"] = .redo

    commands_map["Ctrl-R"] = .search_backward
    commands_map["Ctrl-S"] = .search_forward
}

@(private="file")
_hex_to_color :: proc(hex: int) -> (result: Color) {
    result.r = u8((hex >> 16) & 0xff)
    result.g = u8((hex >> 8) & 0xff)
    result.b = u8((hex) & 0xff)
    result.a = 255
    return
}
