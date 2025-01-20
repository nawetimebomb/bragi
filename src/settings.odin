package main

import "core:strings"

Major_Modes_Map :: map[Major_Mode]Major_Mode_Settings

Major_Mode :: enum {
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

Major_Mode_Settings :: struct {
    enable_lexer       : bool,
    name               : string,
    file_extensions    : string,
    keywords           : []string,
    types              : []string,
    comment_delimiters : string,
    word_delimiters    : string,
    string_delimiters  : string,
    auto_indent_type   : Auto_Indentation_Type,
    indentation_width  : int,
    indentation_char   : Indentation_Char,
}

set_major_modes_settings :: proc() {
    bragi.settings.mm[.Fundamental] = major_mode_fundamental()
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

@(private="file")
major_mode_fundamental :: proc() -> Major_Mode_Settings {
    return {
        enable_lexer       = false,
        name               = "Fundamental",
        word_delimiters    = " \n",
        auto_indent_type   = .Relaxed,
        indentation_width  = 0,
        indentation_char   = .Space,
    }
}

@(private="file")
major_mode_odin :: proc() -> Major_Mode_Settings {
    return {
        enable_lexer      = true,
        name              = "Odin",
        file_extensions   = "odin",
        word_delimiters   = " .,_-[]():\n",
        auto_indent_type  = .Electric,
        indentation_width = 4,
        indentation_char  = .Space,
    }
}
