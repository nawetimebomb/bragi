package main

import "core:fmt"
import "core:slice"
import "core:strings"

Tokenization_Rules :: struct {
    builtins:           []string,
    constants:          []string,
    keywords:           []string,
    comment_delimiters: []string,
    string_delimiters:  []byte,
}

Token_Kind :: enum u8 {
    generic = 0,
    builtin,
    comment,
    constant,
    keyword,
    string,
}

Token :: struct {
    kind: Token_Kind,
    start: int,
    end: int,
}

Tokenizer :: struct {
    column: int,
    line:   int,
    offset: int,
}

@(private="file")
T: ^Tokenizer

@(private="file")
B: ^Buffer

@(private="file")
rules: ^Tokenization_Rules

tokenize_buffer :: proc(b: ^Buffer) {
    // TODO: Should also get the tokenization rules from the buffer
    tokenizer := Tokenizer{ line = 1 }
    tokenization_rules := Tokenization_Rules{}
    T = &tokenizer
    B = b
    rules = &tokenization_rules

    //// TODO: TEMP STUFF // This should be part of the Tokenization_Rules
    builtins := []string{

    }
    constants := []string{ "false", "nil", "true" }
    keywords := []string{
        "asm", "auto_cast", "bit_set", "break", "case", "cast",
        "context", "continue", "defer", "delete", "distinct", "do", "dynamic",
        "else", "enum", "fallthrough", "for", "foreign", "if",
        "import", "in", "map", "not_in", "or_else", "or_return",
        "package", "proc", "return", "struct", "switch", "transmute",
        "typeid", "union", "using", "when", "where", "#load",
    }
    comment_delimiters := []string{ "//", "/*", "*/", }
    string_delimiters := []byte{ '"', '\'', '`' }

    for !is_eof() {
        skip_whitespaces()

        switch {
        case get_char() == '/' && peek_next_char() == '/':
            start := T.offset
            for !is_eof() && get_char() != '\n' { advance() }
            save_tokens(.comment, start, T.offset)
        case is_comment_delimiter(): make_tokens_from_comment()
        case is_string_delimiter():  make_tokens_from_string()
        case is_number():            make_tokens_from_number()
        }

        advance()
    }

    T = nil
    B = nil
    rules = nil
}



@(private="file")
make_tokens_from_comment :: #force_inline proc() {
    has_comment_finished :: proc() -> bool {
        ending_combo := previous_char() == '*' && get_char() == '/'
        previous_two_chars := B.str[T.offset - 2]
        return ending_combo && previous_two_chars != '/'
    }

    t := Token{ kind = .comment, start = T.offset }
    for !is_eof() && !has_comment_finished() { advance() }
    advance()
    t.end = T.offset
    save_token(t)
}

@(private="file")
make_tokens_from_string :: #force_inline proc() {
    t := Token{ kind = .string, start = T.offset }
    starting_char := get_char()
    advance()
    for !is_eof() && get_char() != starting_char { advance() }
    advance()
    t.end = T.offset
    save_token(t)
}

@(private="file")
make_tokens_from_number :: #force_inline proc() {
    t := Token{ kind = .constant, start = T.offset }
    for !is_eof() && is_number() && !is_whitespace() { advance() }
    t.end = T.offset
    save_token(t)
}

@(private="file")
save_tokens :: #force_inline proc(k: Token_Kind, start, end: int) {
    for i in start..<end {
        B.tokens[i] = k
    }
}

@(private="file")
save_token :: #force_inline proc(t: Token) {
    for i in t.start..<t.end {
        B.tokens[i] = t.kind
    }
}

@(private="file")
skip_whitespaces :: #force_inline proc() {
    assert(T != nil && B != nil)

    for c := get_char(); !is_eof() && is_whitespace(); {
        if c == '\n' {
            T.line += 1
            T.column = 0
        }

        advance()
    }
}

@(private="file")
is_comment_delimiter :: #force_inline proc() -> bool {
    c := get_char()
    return (c == '/' && peek_next_char() == '/') ||
        (c == '/' && peek_next_char() == '*')
}

@(private="file")
is_eof :: #force_inline proc() -> bool {
    return T.offset >= len(B.str) - 1
}

@(private="file")
is_whitespace :: #force_inline proc() -> bool {
    c := get_char()
    return c == ' ' || c == '\t' || c == '\n'
}

is_string_delimiter :: #force_inline proc() -> bool {
    // TODO: Use string delimiter from rules
    c := get_char()
    return c == '"' || c == '\'' || c == '`'
}

@(private="file")
is_number :: #force_inline proc() -> bool {
    c := get_char()
    return c >= '0' && c <= '9'
}

@(private="file")
previous_char :: #force_inline proc() -> byte {
    assert(T != nil && B != nil)
    return B.str[T.offset - 1]
}

@(private="file")
get_char :: #force_inline proc() -> byte {
    assert(T != nil && B != nil)
    return B.str[T.offset]
}

@(private="file")
peek_next_char :: #force_inline proc() -> byte {
    assert(T != nil && B != nil)
    return B.str[T.offset + 1]
}

@(private="file")
advance :: #force_inline proc() {
    assert(T != nil && B != nil)
    T.column += 1
    T.offset += 1
}
