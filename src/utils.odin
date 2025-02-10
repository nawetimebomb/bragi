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

scan_through_similar_runes :: proc(
    s: string,
    direction: Direction,
    start_offset: int, count: int = 1,
    rune_cat: Rune_Category = .undefined,
) -> (offset: int) {
    found: int
    pos := start_offset
    match_cat := rune_cat

    if rune_cat == .undefined {
        match_cat = get_rune_category(utf8.rune_at(s, pos))
    }

    for ; pos > 0 && pos < len(s); pos += int(direction) {
        r := utf8.rune_at(s, pos)

        if match_cat != get_rune_category(r) {
            found += 1
        }

        if found == count { break }
    }

    offset = clamp(pos - start_offset, 0, len(s) - 1)
    fmt.println(offset)
    return
}

is_continuation_byte :: proc(b: byte) -> bool {
	return b >= 0x80 && b < 0xc0
}

buffer_cursor_to_view_cursor :: proc(b: ^Buffer, p: Buffer_Cursor) -> (result: [2]int) {
    result.y = get_line_index(b, p)
    bol, _ := get_line_boundaries(b, result.y)
    result.x = p - bol
    return
}

buffer_cursor_to_caret :: proc(b: ^Buffer, pos: Buffer_Cursor) -> (result: Caret_Pos) {
    result.y = get_line_index(b, pos)
    bol, _ := get_line_boundaries(b, result.y)
    result.x = pos - bol
    return
}

get_parsed_length_to_kb :: proc(value_in_bytes: f64) -> string {
    if value_in_bytes == 0 {
        return ""
    } else if value_in_bytes > 1000 * 1000 {
        return fmt.tprintf("%.1fm", value_in_bytes / (1000 * 1000))
    } else if value_in_bytes > 1000 {
        return fmt.tprintf("%.1fk", value_in_bytes / 1000)
    } else {
        return fmt.tprintf("{0}", value_in_bytes)
    }
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
