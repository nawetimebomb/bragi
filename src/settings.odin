package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strconv"
import "core:strings"

PARSE_ERROR_KEYBINDING_EXISTS_FMT :: "Error in line {0}: Keybinding {1} already bound"
PARSE_ERROR_EXPECT_GOT_FMT        :: "Error in line {0}: Invalid setting.\n\tExpect: {1}\n\tGot: {2}"
PARSE_ERROR_INVALID_COMMAND_FMT   :: "Error in line {0}: Invalid command {1}"
PARSE_ERROR_INVALID_FACE_FMT      :: "Error in line {0}: Invalid face name {1}"
PARSE_ERROR_MISSING_HEADING_FMT   :: "Error in line {0}: Heading not found, not able to determine configuration"

Color :: distinct [4]u8
Major_Modes_Table :: map[Major_Mode]Major_Mode_Settings
Colorscheme_Table :: map[Face]Color
Keybindings_Table :: map[string]Command

DEFAULT_COLORSCHEME :: #load("../res/config.bragi")

Major_Mode :: enum {
    Bragi,
    Fundamental,
    Odin,
}

Indentation_Char :: enum { Space, Tab, }

// Indentation Type:
//   It's a convenience feature to make the buffer understand how it should be indented
//   Off: No indentation, always goes to start of line
//   Relaxed: Matches the indentation of the current line, before the newline jump
//   Electric: Matches the configuration of the Major Mode
Auto_Indentation_Type  :: enum { Off, Relaxed, Electric, }

Face :: enum {
    background,
    cursor,
    builtin,
    comment,
    constant,
    default,
    highlight,
    highlight_line,
    keyword,
    region,
    string,
    type,

    modeline_off_bg,
    modeline_off_fg,
    modeline_on_bg,
    modeline_on_fg,
    modeline_shadow,

    ui_border,
}

Settings :: struct {
    handle:                      os.Handle,
    last_write_time:             os.File_Time,
    use_internal_data:           bool,

    colorscheme_table:           Colorscheme_Table,
    keybindings_table:           Keybindings_Table,
    major_modes_table:           Major_Modes_Table,

    cursor_blink_timeout:        f32,
    font_size:                   u32,
    remove_trailing_whitespaces: bool,
    save_desktop_mode:           bool,
    show_line_numbers:           bool,
}

Major_Mode_Settings :: struct {
    enable_lexer:       bool,
    name:               string,
    file_extensions:    string,
    word_delimiters:    string,
    auto_indent_type:   Auto_Indentation_Type,
    indentation_width:  int,
    indentation_char:   Indentation_Char,
}

set_major_modes_settings :: proc() {
    bragi.settings.major_modes_table[.Fundamental] = major_mode_fundamental()
    bragi.settings.major_modes_table[.Bragi]       = major_mode_bragi()
    bragi.settings.major_modes_table[.Odin]        = major_mode_odin()
}

find_major_mode :: proc(file_ext: string) -> Major_Mode {
    if len(file_ext) > 0 {
        for key, value in bragi.settings.major_modes_table {
            if strings.contains(value.file_extensions, file_ext) {
                return key
            }
        }
    }

    return .Fundamental
}

settings_get_word_delimiters :: proc(mode: Major_Mode) -> string {
    return bragi.settings.major_modes_table[mode].word_delimiters
}

settings_get_major_mode_name :: proc(mm: Major_Mode) -> string {
    return bragi.settings.major_modes_table[mm].name
}

settings_is_lexer_enabled :: proc(mm: Major_Mode) -> bool {
    return bragi.settings.major_modes_table[mm].enable_lexer
}

load_settings_from_internal_data :: proc() {
    log.debug("Loading settings from internal program data")
    bragi.settings.use_internal_data = true
    load_settings(SETTINGS_DATA)
}

load_settings_from_file :: proc() {
    data, err := os.read_entire_file_or_err(
        bragi.settings.handle,
        context.temp_allocator,
    )

    if err != nil {
        load_settings_from_internal_data()
        log.errorf("Failed to load settings from file {0}", err)
        return
    }

    log.debugf("Loading settings from file {0}", SETTINGS_FILENAME)
    bragi.settings.use_internal_data = false
    os.seek(bragi.settings.handle, 0, 0)
    load_settings(data)
}

load_settings :: proc(data: []u8) {
    set_major_modes_settings()
    parse_settings_data(data)
}

parse_settings_data :: proc(data: []u8) {
    Parsing_Setting :: enum {
        none,
        colors,
        keybindings,
    }

    is_not_empty :: proc(s: string) -> bool {
        return len(s) > 0
    }

    currently_parsing: Parsing_Setting
    line_number := 0
    settings_str := string(data)

    clear(&bragi.settings.colorscheme_table)
    for key, _ in bragi.settings.keybindings_table {
        delete(key)
    }
    clear(&bragi.settings.keybindings_table)

    for line in strings.split_lines_iterator(&settings_str) {
        line_number += 1

        // Look for a heading
        switch {
        case strings.starts_with(line, "#"):
            // Skip a commentary line
            continue
        case strings.starts_with(line, "[keybindings]"):
            // Preparing for parsing keybindings
            currently_parsing = .keybindings
            continue
        case strings.starts_with(line, "[colors]"):
            // Preparing for parsing keybindings
            currently_parsing = .colors
            continue
        case :
            sl := strings.split(line, " ", context.temp_allocator)
            setting := slice.filter(sl, is_not_empty, context.temp_allocator)

            if len(setting) == 0 { continue }

            switch currently_parsing {
            case .none:
                log.errorf(PARSE_ERROR_MISSING_HEADING_FMT, line_number)
                return
            case .keybindings:
                if len(setting) < 2 {
                    log.errorf(
                        PARSE_ERROR_EXPECT_GOT_FMT,
                        line_number,
                        "command <keybinding>",
                        line,
                    )
                    continue
                }

                command, ok := reflect.enum_from_name(Command, setting[0])

                if !ok {
                    log.errorf(
                        PARSE_ERROR_INVALID_COMMAND_FMT,
                        line_number,
                        setting[0],
                    )
                    continue
                }

                for i in 1..<len(setting) {
                    k := setting[i]

                    if !strings.starts_with(k, "<") || !strings.ends_with(k, ">") {
                        log.errorf(
                            PARSE_ERROR_EXPECT_GOT_FMT,
                            line_number,
                            "<keybinding>",
                            line,
                        )
                        continue
                    }

                    bind := k[1:len(k) - 1]

                    _, exists := bragi.settings.keybindings_table[bind]

                    if exists {
                        log.errorf(
                            PARSE_ERROR_KEYBINDING_EXISTS_FMT,
                            line_number,
                            k,
                        )
                        continue
                    }

                    bragi.settings.keybindings_table[strings.clone(bind)] = command
                }

            case .colors:
                if len(setting) != 2 {
                    log.errorf(
                        PARSE_ERROR_EXPECT_GOT_FMT,
                        line_number,
                        "face color",
                        line,
                    )
                    continue
                }

                v, ok := reflect.enum_from_name(Face, setting[0])

                if !ok {
                    log.errorf(
                        PARSE_ERROR_INVALID_FACE_FMT,
                        line_number,
                        setting[0],
                    )
                    continue
                }

                bragi.settings.colorscheme_table[v] = hex_to_color(setting[1])
            }
        }
    }
}

reload_settings :: proc() {
    if !bragi.settings.use_internal_data {
        last_write_time, err := os.last_write_time(bragi.settings.handle)

        if err == nil && bragi.settings.last_write_time != last_write_time {
            bragi.settings.last_write_time = last_write_time
            load_settings_from_file()
        }
    }
}

@(private="file")
hex_to_color :: proc(hex_str: string) -> Color {
    color: Color
    value, ok := strconv.parse_int(hex_str, 16)

    if !ok {
        log.errorf("Cannot parse color {0}", hex_str)
        return color
    }

    color.r = u8((value >> 16) & 0xFF)
    color.g = u8((value >> 8) & 0xFF)
    color.b = u8((value) & 0xFF)
    color.a = 255

    return color
}

@(private="file")
major_mode_bragi :: proc() -> Major_Mode_Settings {
    return {
        auto_indent_type  = .Relaxed,
        enable_lexer      = true,
        file_extensions   = "bragi",
        indentation_char  = .Space,
        indentation_width = 0,
        name              = "Bragi",
        word_delimiters   = " \n",
    }
}

@(private="file")
major_mode_fundamental :: proc() -> Major_Mode_Settings {
    return {
        auto_indent_type   = .Relaxed,
        enable_lexer       = false,
        indentation_char   = .Space,
        indentation_width  = 0,
        name               = "Fundamental",
        word_delimiters    = " \n",
    }
}

@(private="file")
major_mode_odin :: proc() -> Major_Mode_Settings {
    return {
        auto_indent_type  = .Electric,
        enable_lexer      = true,
        file_extensions   = "odin",
        indentation_char  = .Space,
        indentation_width = 4,
        name              = "Odin",
        word_delimiters   = " .,_-[]():\n",
    }
}
