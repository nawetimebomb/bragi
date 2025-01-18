package main

Major_Mode :: enum {
    Fundamental,
    Odin,
}

Major_Mode_Settings :: struct {
    enable_lexer       : bool,
    name               : string,
    file_extensions    : []string,
    keywords           : []string,
    types              : []string,
    comment_delimiters : string,
    word_delimiters    : string,
    string_delimiters  : string,
}

set_major_modes_settings :: proc() {
    bragi.ctx.mm_settings[.Fundamental] = major_mode_fundamental()
    bragi.ctx.mm_settings[.Odin] = major_mode_odin()
}

@(private="file")
major_mode_fundamental :: proc() -> Major_Mode_Settings {
    return {
        enable_lexer = false,
        name = "Fundamental",
        word_delimiters = " \n",
    }
}

@(private="file")
major_mode_odin :: proc() -> Major_Mode_Settings {
    return {
        enable_lexer = true,
        name = "Odin",
        file_extensions = { ".odin" },
        word_delimiters = " .,_-[]():\n",
    }
}
