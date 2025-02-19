#+private file

package main

import "core:reflect"
import "core:slice"
import "core:strings"

Odin_Keyword :: enum u8 {
    k_align_of, k_asm, k_auto_cast, k_break, k_case, k_cast, k_container_of, k_context,
    k_continue, k_defer, k_distinct, k_do, k_dynamic, k_else, k_enum, k_fallthrough,
    k_for, k_foreign, k_if, k_in, k_import, k_not_in, k_offset_of, k_or_else,
    k_or_return, k_or_break, k_or_continue, k_package, k_proc, k_return, k_size_of,
    k_struct, k_switch, k_transmute, k_typeid_of, k_type_info_of, k_type_of, k_union,
    k_using, k_when, k_where,
}

Odin_Operation :: enum u8 {
    colon, colon_colon, colon_equal,
    period_period, period_question, period_period_equal, period_period_less,
    slash, slash_equal,
}

Odin_Punctuation :: enum u8 {
    attribute, brace_l, brace_r, bracket_l, bracket_r, caret, comma, dollar,
    newline, paren_l, paren_r, period, question, semicolon,
}

Token :: struct {
    start, length: int,
    kind: Token_Kind,

    v: union {
        Odin_Keyword,
        Odin_Operation,
        Odin_Punctuation,
    },
}

Odin_Tokenizer :: struct {
    using t: Tokenizer,

    previous: [3]Token,
}

@private
tokenize_odin :: proc(b: ^Buffer, start := -1, end := -1) -> []Buffer_Section {
    tokenizer := start_odin_tokenizer(b, start, end)
    result := make([dynamic]Buffer_Section, 0, 0, context.temp_allocator)

    for {
        token := get_next_token(&tokenizer)
        if token.kind == .eof { break }
        prev1, prev2, prev3 := get_previous_tokens(&tokenizer)

        should_highlight_previous_two :: proc(curr, prev1, prev2: ^Token) -> bool {
            if curr.kind == .keyword &&
                (curr.v == .k_proc) &&
                prev1.kind == .operation && prev1.v == .colon_colon {
                    prev2.kind = .function
                    return true
                }
            return false
        }

        should_highlight_previous :: proc(curr, prev1: ^Token) -> bool {
            if curr.kind == .punctuation && curr.v == .paren_l &&
                prev1.kind == .identifier {
                    prev1.kind = .function
                    return true
                }
            return false
        }

        if should_highlight_previous_two(&token, &prev1, &prev2) {
            save_token(b, prev2.start, prev2.length, prev2.kind)
        }

        if should_highlight_previous(&token, &prev1) {
            save_token(b, prev1.start, prev1.length, prev1.kind)
        }

        // Figuring out trailing whitespaces
        // TODO: Should add settings check here so I don't do it if it's not needed
        if bragi.settings.show_trailing_whitespaces {
            if token.v == .newline && tokenizer.whitespace_to_left {
                start := prev1.start + prev1.length

                append(&result, Buffer_Section{
                    start = start,
                    end = token.start,
                    kind = .trailing_whitespace,
                })
            }
        }

        tokenizer.previous[2] = prev2
        tokenizer.previous[1] = prev1
        tokenizer.previous[0] = token

        save_token(b, token.start, token.length, token.kind)
    }

    return slice.clone(result[:])
}

start_odin_tokenizer :: proc(b: ^Buffer, start, end: int) -> (t: Odin_Tokenizer) {
    result: Odin_Tokenizer
    setup_tokenizer(&result, b, start, end)
    return result
}

get_previous_tokens :: proc(t: ^Odin_Tokenizer) -> (p1, p2, p3: Token) {
    p1 = t.previous[0]
    p2 = t.previous[1]
    p3 = t.previous[2]
    return
}

get_next_token :: proc(t: ^Odin_Tokenizer) -> (token: Token) {
    skip_whitespaces(t)

    token.start = t.offset
    token.kind = .eof

    if is_eof(t) { return }

    if is_alpha(t) || is_char(t, '_') {
        parse_identifier(t, &token)
    } else if is_number(t) {
        parse_number(t, &token)
    } else {
        switch get_char_at(t) {
        case '/': parse_single_slash(t, &token)
        case ':': parse_colon(t, &token)
        case '.': parse_period(t, &token)

        case '\'': fallthrough
        case '`':  fallthrough
        case '"':  parse_string_literal(t, &token)

        case ';':  token.kind = .punctuation; token.v = .semicolon; t.offset += 1
        case ',':  token.kind = .punctuation; token.v = .comma;     t.offset += 1
        case '^':  token.kind = .punctuation; token.v = .caret;     t.offset += 1
        case '?':  token.kind = .punctuation; token.v = .question;  t.offset += 1
        case '{':  token.kind = .punctuation; token.v = .brace_l;   t.offset += 1
        case '}':  token.kind = .punctuation; token.v = .brace_r;   t.offset += 1
        case '(':  token.kind = .punctuation; token.v = .paren_l;   t.offset += 1
        case ')':  token.kind = .punctuation; token.v = .paren_r;   t.offset += 1
        case '[':  token.kind = .punctuation; token.v = .bracket_l; t.offset += 1
        case ']':  token.kind = .punctuation; token.v = .bracket_r; t.offset += 1
        case '$':  token.kind = .punctuation; token.v = .dollar;    t.offset += 1
        case '@':  token.kind = .punctuation; token.v = .attribute; t.offset += 1
        case '\n': token.kind = .punctuation; token.v = .newline;   t.offset += 1

        case : token.kind = .invalid; t.offset += 1
        }
    }

    token.length = t.offset - token.start

    return
}

peek_next_token :: proc(t: ^Odin_Tokenizer) -> (token: Token) {
    t2 := t^
    return get_next_token(&t2)
}

parse_colon :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .operation
    token.v = .colon

    t.offset += 1
    if is_eof(t) { return }

    switch get_char_at(t) {
    case ':': token.v = .colon_colon
    case '=': token.v = .colon_equal
    }

    t.offset += 1
}

parse_identifier :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .identifier

    word := get_word_at(t)
    try_keyword := strings.concatenate([]string{"k_", word}, context.temp_allocator)

    if v, ok := reflect.enum_from_name(Odin_Keyword, try_keyword); ok {
        token.kind = .keyword
        token.v = v
    } else if slice.contains([]string{"nil", "true", "false"}, word) {
        token.kind = .constant
    }
}

parse_number :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .constant
    get_word_at(t)
}

parse_period :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .punctuation
    token.v = .period

    t.offset += 1
    if is_eof(t) { return }

    switch get_char_at(t)  {
    case '?':
        token.kind = .operation
        token.v = .period_question
    case '.':
        token.kind = .operation
        token.v = .period_period

        t.offset += 1
        if is_eof(t) { return }

        switch get_char_at(t) {
        case '=': token.v = .period_period_equal; t.offset += 1
        case '<': token.v = .period_period_less;  t.offset += 1
        }
    case :
        prev1, _, _ := get_previous_tokens(t)

        if prev1.kind != .identifier && t.whitespace_to_left {
            next_token := peek_next_token(t)

            if next_token.kind == .identifier {
                token.kind = .enum_variant
                token.v = nil
                t.offset += next_token.length
            }
        }
    }
}

parse_single_slash :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    t.offset += 1

    token.kind = .operation
    token.v = .slash

    if is_eof(t) { return }

    switch get_char_at(t) {
    case '=':
        token.v = .slash_equal
    case '/':
        token.kind = .comment
        token.v = nil
        for !is_eof(t) && !is_char(t, '\n') { t.offset += 1 }
    case '*':
        token.kind = .comment_multiline
        token.v = nil
        t.offset += 1
        nested_comments_count := 0

        for !is_eof(t) {
            current := get_char_at(t)
            next := get_char_at(t, 1)

            if current == '/' && next == '*' {
                t.offset += 2
                nested_comments_count += 1
            } else if current == '*' && next == '/' {
                if nested_comments_count == 0 {
                    t.offset += 2
                    break
                } else {
                    nested_comments_count -= 1
                    t.offset += 2
                }
            } else {
                t.offset += 1
            }
        }
    }
}

parse_string_literal :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    delimiter := get_char_at(t)

    if is_eof(t) { return }
    t.offset += 1

    if delimiter == '`' {
        token.kind = .string_raw
        for !is_eof(t) && !is_char(t, delimiter) { t.offset += 1 }
    } else {
        token.kind = .string_literal
        is_escaped := false

        for !is_eof(t) {
            if is_char(t, delimiter) && !is_escaped { break }
            is_escaped = !is_escaped && is_char(t, '\\')
            t.offset += 1
        }
    }

    if is_eof(t) { return }
    t.offset += 1
}
