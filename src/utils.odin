package main

import "core:fmt"
import "core:log"
import "core:strings"
import "core:unicode/utf8"

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

move_to :: proc(d: []u8, start, count: int, stop_on_newline := true) -> (end: int) {
    max_offset := start + count
    offset := 0

    for pos := start; pos < max_offset && pos < len(d); pos += 1 {
        if stop_on_newline && d[pos] == '\n' { break }
        offset += 1
    }

    return start + offset
}

canonicalize_coords :: proc(d: []u8, rel_x, rel_y: int) -> (point: int) {
    x, y: int

    for r, index in d {
        if y == rel_y {
            bol, eol := get_line_boundaries(d, index)
            length := eol - bol
            point = length > rel_x ? bol + rel_x : eol
        }

        x = r == '\n' ? 0 : x + 1
        y = r == '\n' ? y + 1 : y
    }

    return
}

get_standard_character_size :: proc() -> (char_width, line_length: i32) {
    M_char_rect := bragi.ctx.characters['M'].dest
    return M_char_rect.w, M_char_rect.h
}

get_next_line_start_index :: proc(d: []u8, pos: int) -> (index: int) {
    _, eol := get_line_boundaries(d, pos)
    return eol + 1
}

get_previous_line_start_index :: proc(d: []u8, pos: int) -> (index: int) {
    bol, _ := get_line_boundaries(d, pos)
    index, _ = get_line_boundaries(d, bol - 1)
    return
}

// Change this to use array of data
get_line_boundaries :: proc(d: []u8, pos: int) -> (begin, end: int) {
    begin = pos; end = pos

    for {
        bsearch := begin > 0 && d[begin - 1] != '\n'
        esearch := end < len(d) - 1 && d[end] != '\n'
        if bsearch { begin -= 1 }
        if esearch { end += 1 }
        if !bsearch && !esearch { return }
    }
}

get_line_length :: proc(d: []u8, pos: int) -> int {
    bol, eol := get_line_boundaries(d, pos)
    return eol - bol
}

get_word_boundaries :: proc(s: string, pos: int) -> (begin, end: int) {
    begin = pos; end = pos

    for {
        brtype := get_rune_type(utf8.rune_at(s, begin - 1))
        ertype := get_rune_type(utf8.rune_at(s, end))
        bsearch := begin > 0 && (brtype == .alpha || brtype == .numeric)
        esearch := end < len(s) - 1 && (ertype == .alpha || ertype == .numeric)
        if bsearch { begin -= 1 }
        if esearch { end += 1 }
        if !bsearch && !esearch { return }
    }
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

is_common_delimiter :: #force_inline proc(r: rune) -> bool {
    DELIMITERS :: ".,()[]{}"
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
