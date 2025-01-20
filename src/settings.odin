package main

import "core:log"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"

Color :: distinct [4]u8
Major_Modes_Map :: map[Major_Mode]Major_Mode_Settings
Colorscheme :: map[Face]Color

// NOTE:
//   ^Render_State is .Default, .Keyword, etc
//   ^string is the buffer string
//   int is the cursor position
// Lexer_Proc :: #type proc(^Render_State, ^string, int)

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
    builtin_bg,
    builtin_fg,

    comment_bg,
    comment_fg,

    constant_bg,
    constant_fg,

    cursor_bg,
    cursor_fg,

    default_bg,
    default_fg,

    keyword_bg,
    keyword_fg,

    match_delimiter_bg,
    match_delimiter_fg,

    match_highlight_bg,
    match_highlight_fg,

    modeline_off_bg,
    modeline_off_fg,

    modeline_on_bg,
    modeline_on_fg,

    region_bg,
    region_fg,

    string_bg,
    string_fg,
}

Major_Mode_Settings :: struct {
    enable_lexer:       bool,
    name:               string,
    file_extensions:    string,
    keywords:           []string,
    types:              []string,
    comment_delimiters: string,
    word_delimiters:    string,
    string_delimiters:  string,
    auto_indent_type:   Auto_Indentation_Type,
    indentation_width:  int,
    indentation_char:   Indentation_Char,
}

set_major_modes_settings :: proc() {
    bragi.settings.mm[.Fundamental] = major_mode_fundamental()
    bragi.settings.mm[.Bragi]       = major_mode_bragi()
    bragi.settings.mm[.Odin]        = major_mode_odin()
}

find_major_mode :: proc(file_ext: string) -> Major_Mode {
    if len(file_ext) > 0 {
        for key, value in bragi.settings.mm {
            if strings.contains(value.file_extensions, file_ext) {
                return key
            }
        }
    }

    return .Fundamental
}

get_word_delimiters :: proc(mode: Major_Mode) -> string {
    return bragi.settings.mm[mode].word_delimiters
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

    settings_str := string(data)
    for line in strings.split_lines_iterator(&settings_str) {
        s := strings.split(line, " ", context.temp_allocator)
        key := strings.trim_space(s[0])
        value := strings.trim_space(s[len(s) - 1])

        if face, ok := reflect.enum_from_name(Face, key); ok {
            bragi.settings.colors[face] = hex_to_color(value)
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
