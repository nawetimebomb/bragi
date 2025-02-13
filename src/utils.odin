package main

import "core:fmt"
import "core:log"
import "core:strings"
import "core:time"
import "core:unicode/utf8"
import "tokenizer"

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

get_rune_category :: proc(r: rune) -> Rune_Category {
    switch get_rune_type(r) {
    case .alpha, .numeric:          return .word
    case .punctuation, .whitespace: return .non_word
    case .unknown:
        log.errorf("Could not find a category for rune {0}", r)
    }

    return .non_word
}

get_rune_type :: proc(r: rune) -> Rune_Type {
    switch {
    case is_alpha(r):             return .alpha
    case is_number(r):            return .numeric
    case is_common_delimiter(r):  return .punctuation
    case is_whitespace(r):        return .whitespace
    case :
        log.errorf("Could not find a type for rune {0}", r)
    }

    return .unknown
}

is_alpha :: #force_inline proc(r: rune) -> bool {
    return is_alpha_lowercase(r) || is_alpha_uppercase(r)
}

is_alpha_lowercase :: #force_inline proc(r: rune) -> bool {
    return r >= 'a' && r <= 'z'
}

is_alpha_uppercase :: #force_inline proc(r: rune) -> bool {
    return r >= 'A' && r <= 'Z'
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

is_number :: #force_inline proc(r: rune) -> bool {
    return r >= '0' && r <= '9'
}

is_whitespace :: proc{
    is_char_whitespace,
    is_rune_whitespace,
}

is_char_whitespace :: #force_inline proc(b: byte) -> bool {
    return b == ' ' || b == '\t' || b == '\n'
}

is_rune_whitespace :: #force_inline proc(r: rune) -> bool {
    return r == ' ' || r == '\t' || r == '\n'
}

is_newline :: #force_inline proc(b: byte) -> bool {
    return b == '\n'
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
    case .Odin:        result = tokenizer.odin_punctuations()
    }

    return result
}
