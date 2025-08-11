package main

import "core:fmt"
import "core:log"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

UPPERCASE_CHARS :: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

Direction :: enum int {
    left = -1, right = 1,
}

Rune_Type :: enum {
    alpha,
    numeric,
    punctuation,
    unknown,
    whitespace,
}

Rune_Category :: enum {
    undefined,
    non_word,
    word,
}

add :: proc{
    add_buffer,
    add_pane,
}

add_buffer :: proc(b: Buffer) -> ^Buffer {
    _, err := append(&open_buffers, b)
    assert(err == .None, "Cannot append new buffer")
    return &open_buffers[len(open_buffers) - 1]
}

add_pane :: proc(p: Pane) -> ^Pane {
    _, err := append(&open_panes, p)
    assert(err == .None, "Cannot append new pane")
    resize_panes()
    return &open_panes[len(open_panes) - 1]
}

is_common_delimiter :: proc{
    is_common_delimiter_char,
    is_common_delimiter_rune,
}

is_common_delimiter_char :: #force_inline proc(c: byte) -> bool {
    return is_common_delimiter_rune(rune(c))
}

is_common_delimiter_rune :: #force_inline proc(r: rune) -> bool {
    DELIMITERS :: " /\\.,()[]{}"
    return strings.contains_rune(DELIMITERS, r)
}

// TODO: this needs to be removed once the tokenizer is fully working
is_whitespace_temp :: proc(c: byte) -> bool {
    return c == ' ' || c == '\t' || c == '\n'
}

get_dir_and_filename_from_fullpath :: proc(s: string) -> (dir, filename: string) {
    last_slash_index := strings.last_index(s, "/")

    if last_slash_index == -1 {
        last_slash_index = strings.last_index(s, "\\")
    }

    dir = s[:last_slash_index + 1]
    filename = s[last_slash_index + 1:]

    return
}

get_base_os_dir :: #force_inline proc() -> string {
    return "/"
}

get_month_string :: #force_inline proc(m: time.Month) -> string {
    mstr := ""

    switch m {
    case .January:   mstr = "Jan"
	case .February:  mstr = "Feb"
	case .March:     mstr = "Mar"
	case .April:     mstr = "Apr"
	case .May:       mstr = "May"
	case .June:      mstr = "Jun"
	case .July:      mstr = "Jul"
	case .August:    mstr = "Aug"
	case .September: mstr = "Sep"
	case .October:   mstr = "Oct"
	case .November:  mstr = "Nov"
	case .December:  mstr = "Dec"
    }

    return mstr
}

get_punctuations :: proc(m: Major_Mode) -> string {
    result := ""
    DEFAULT_PUNCTUATIONS :: " \t\n"

    switch m {
    case .Fundamental: result = DEFAULT_PUNCTUATIONS
    case .Bragi:
    case .Odin:        result = " ()[]:;,.\n"
    }

    return result
}
