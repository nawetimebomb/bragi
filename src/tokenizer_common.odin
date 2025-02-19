package main

import "core:strings"

Token_Kind :: enum u8 {
    generic = 0,
    eof,
    invalid,
    error,

    char_literal,
    string_literal,
    string_raw,

    comment,
    comment_multiline,

    identifier,
    operation,
    punctuation,

    constant,
    directive,
    enum_variant,
    function,
    keyword,
    type,

    builtin_function,
    builtin_variable,
}

Tokenizer :: struct {
    buf: string,
    offset, max_offset: int,
    whitespace_to_left: bool,
}

start_tokenizer :: proc(b: ^Buffer, start, end: int) -> (t: Tokenizer) {
    result: Tokenizer
    setup_tokenizer(&result, b, start, end)
    return result
}

setup_tokenizer :: proc(t: ^Tokenizer, b: ^Buffer, start, end: int) {
    t.buf = b.str
    t.offset = clamp(start, 0, len(b.str) - 1)
    t.max_offset = clamp(end, 0, len(b.str) - 1)

    if end == -1 {
        t.max_offset = len(b.str) - 1
    }
}

save_token :: #force_inline proc(b: ^Buffer, start, length: int, kind: Token_Kind) {
    end := start + length
    for i in start..<end { b.tokens[i] = kind }
}

get_char_at :: #force_inline proc(t: ^Tokenizer, offset: int = 0) -> byte {
    return t.buf[t.offset + offset]
}

get_word_at :: #force_inline proc(t: ^Tokenizer) -> string {
    result := strings.builder_make(context.temp_allocator)

    for !is_eof(t) && is_valid_word_component(t) {
        strings.write_byte(&result, get_char_at(t))
        t.offset += 1
    }

    return strings.to_string(result)
}

skip_whitespaces :: #force_inline proc(t: ^Tokenizer) {
    old_offset := t.offset
    for !is_eof(t) && is_whitespace(t) { t.offset += 1 }
    t.whitespace_to_left = t.offset != old_offset
}

is_alpha :: #force_inline proc(t: ^Tokenizer) -> bool {
    return is_alpha_lowercase(t) || is_alpha_uppercase(t)
}

is_alphanumeric :: #force_inline proc(t: ^Tokenizer) -> bool {
    return is_alpha(t) || is_number(t)
}

is_alpha_lowercase :: #force_inline proc(t: ^Tokenizer) -> bool {
    c := get_char_at(t)
    return c >= 'a' && c <= 'z'
}

is_alpha_uppercase :: #force_inline proc(t: ^Tokenizer) -> bool {
    c := get_char_at(t)
    return c >= 'A' && c <= 'Z'
}

is_char :: #force_inline proc(t: ^Tokenizer, c: byte) -> bool {
    return get_char_at(t) == c
}

is_eof :: #force_inline proc(t: ^Tokenizer) -> bool {
    return t.offset >= t.max_offset
}

is_newline :: #force_inline proc(t: ^Tokenizer) -> bool {
    c := get_char_at(t)
    return c == '\n'
}

is_number :: #force_inline proc(t: ^Tokenizer) -> bool {
    c := get_char_at(t)
    return c >= '0' && c <= '9'
}

is_valid_word_component :: #force_inline proc(t: ^Tokenizer) -> bool {
    return is_alpha(t) || is_number(t) || is_char(t, '_')
}

is_whitespace :: #force_inline proc(t: ^Tokenizer) -> bool {
    c := get_char_at(t)
    return c == ' ' || c == '\t'
}
