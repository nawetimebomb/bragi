package languages

import "core:strings"
import "core:slice"

Render_State_Face :: enum {
    Default,

    Builtin,
    Comment,
    Constant,
    Keyword,
    Highlight,
    String,
}

Render_State :: struct {
    cursor:       int,
    end_of_line:  int,
    line:         string,
    length:       int,
    current_rune: rune,
    state:        Render_State_Face,
}

ASCII_CHARS :: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

is_char_ascii :: proc(c: u8) -> bool {
    if ascii_set, ok := strings.ascii_set_make(ASCII_CHARS); ok {
        return strings.ascii_set_contains(ascii_set, c)
    } else {
        return is_ascii(rune(c))
    }
}

is_rune_ascii :: proc(r: rune) -> bool {
    return strings.contains_rune(ASCII_CHARS, r)
}

is_ascii :: proc{
    is_char_ascii,
    is_rune_ascii,
}

match_words :: proc(str: string, start_pos: int, words: []string) -> (length: int, found: bool) {
    end_pos: int

    for x := start_pos; x < len(str); x += 1 {
        if !is_ascii(str[x]) {
            end_pos = x
            break
        }
    }

    if end_pos > start_pos {
        word := str[start_pos:end_pos]
        length = len(word)
        found = slice.contains(words, word)
    }

    return
}
