#+private file

package main

import "core:fmt"
import "core:reflect"
import "core:slice"
import "core:strings"

Odin_Directive :: enum u8 {
    d_packed, d_sparse, d_raw_union, d_align,
    d_shared_nil, d_no_nil,
    d_type, d_subtype,
    d_partial, d_unroll, d_reverse,
    d_no_alias, d_any_int, d_c_vararg, d_by_ptr, d_const,
    d_optional_ok, d_optional_allocator_error,
    d_bounds_check, d_no_bounds_check,
    d_force_inline, d_no_force_inline,
    d_assert, d_panic,
    d_config, d_defined, d_exists,
    d_location, d_caller_location,
    d_file, d_line, d_procedure, d_directory, d_hash,
    d_load, d_load_or, d_load_directory, d_load_hash,
    d_soa, d_relative, d_simd,
}

Odin_Keyword :: enum u8 {
    k_align_of, k_asm, k_auto_cast, k_break, k_case, k_cast, k_container_of, k_context,
    k_continue, k_defer, k_distinct, k_do, k_dynamic, k_else, k_enum, k_fallthrough,
    k_for, k_foreign, k_if, k_in, k_import, k_not_in, k_offset_of, k_or_else,
    k_or_return, k_or_break, k_or_continue, k_package, k_proc, k_return, k_size_of,
    k_struct, k_switch, k_transmute, k_typeid_of, k_type_info_of, k_type_of, k_union,
    k_using, k_when, k_where,
}

Odin_Operation :: enum u8 {
    ampersand, ampersand_ampersand, ampersand_equal, ampersand_tilde,
    ampersand_tilde_equal, arrow, bang, bang_equal, colon, colon_colon, colon_equal,
    equal, equal_equal, dash, dash_equal, greater, greater_equal, greater_greater,
    greater_greater_equal, less, less_equal, less_less, less_less_equal, percent,
    percent_equal, percent_percent, percent_percent_equal, period_period, period_question,
    period_period_equal, period_period_less, pipe, pipe_pipe, pipe_equal,
    pipe_pipe_equal, plus, plus_equal, slash, slash_equal, star,
    star_equal, tilde, tilde_equal,
}

Odin_Punctuation :: enum u8 {
    attribute, brace_l, brace_r, bracket_l, bracket_r, caret, comma, dollar,
    newline, paren_l, paren_r, period, question, semicolon,
}

Odin_Type :: enum u8 {
    t_bool, t_b8, t_b16, t_b32, t_b64, t_int,  t_i8, t_i16, t_i32, t_i64, t_i128,
    t_uint, t_u8, t_u16, t_u32, t_u64, t_u128, t_uintptr, t_byte,
    t_i16le, t_i32le, t_i64le, t_i128le, t_u16le, t_u32le, t_u64le, t_u128le,
    t_i16be, t_i32be, t_i64be, t_i128be, t_u16be, t_u32be, t_u64be, t_u128be,
    t_f16, t_f32, t_f64, t_f16le, t_f32le, t_f64le, t_f16be, t_f32be, t_f64be,
    t_complex32, t_complex64, t_complex128, t_quaternion64, t_quaternion128,
    t_quaternion256, t_rune, t_string, t_cstring, t_rawptr, t_typeid, t_any,
    t_matrix, t_map, t_bit_set, t_Maybe,
}

Token :: struct {
    start, length: int,
    kind: Token_Kind,
    v: union {
        Odin_Directive,
        Odin_Keyword,
        Odin_Operation,
        Odin_Punctuation,
        Odin_Type,
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
            if (curr.v == .k_proc || curr.v == .d_force_inline) &&
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

        if token.kind == .invalid {
            fmt.println(
                "INVALID TOKEN", token,
                b.str[token.start:token.start+token.length],
            )
        }

        tokenizer.previous[2] = prev2
        tokenizer.previous[1] = prev1
        tokenizer.previous[0] = token

        save_token(b, token.start, token.length, token.kind)
    }

    return slice.clone(result[:])
}

@private
tokenize_odin_indent :: proc(b: ^Buffer, start, end: int) -> []Indent_Token {
    tokenizer := start_odin_tokenizer(b, start, end)
    result := make([dynamic]Indent_Token, 0, 0, context.temp_allocator)

    for {
        token := get_next_token(&tokenizer)
        if token.kind == .eof { break }

        it: Indent_Token

        if token.kind == .punctuation {
            switch token.v {
            case .brace_l:   it.action = .open; it.kind = .brace
            case .bracket_l: it.action = .open; it.kind = .bracket
            case .paren_l:   it.action = .open; it.kind = .paren

            case .brace_r:   it.action = .close; it.kind = .brace
            case .bracket_r: it.action = .close; it.kind = .bracket
            case .paren_r:   it.action = .close; it.kind = .paren
            case : continue
            }

            append(&result, it)
        }
    }

    return result[:]
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
        case '!':  parse_bang     (t, &token)
        case '#':  parse_directive(t, &token)
        case '%':  parse_percent  (t, &token)
        case '&':  parse_ampersand(t, &token)
        case '*':  parse_star     (t, &token)
        case '+':  parse_plus     (t, &token)
        case '-':  parse_dash     (t, &token)
        case '.':  parse_period   (t, &token)
        case '/':  parse_slash    (t, &token)
        case ':':  parse_colon    (t, &token)
        case '<':  parse_less     (t, &token)
        case '=':  parse_equal    (t, &token)
        case '>':  parse_greater  (t, &token)
        case '\t': parse_tab      (t, &token)
        case '|':  parse_pipe     (t, &token)
        case '~':  parse_tilde    (t, &token)

        case '\'': fallthrough
        case '`':  fallthrough
        case '"':  parse_string   (t, &token)

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

        case :     token.kind = .invalid; t.offset += 1
        }
    }

    token.length = t.offset - token.start

    return
}

peek_next_token :: proc(t: ^Odin_Tokenizer) -> (token: Token) {
    t2 := t^
    token = get_next_token(&t2)
    t.whitespace_to_right = t2.whitespace_to_left
    return
}

parse_ampersand :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .operation
    token.v = .ampersand

    t.offset += 1
    if is_eof(t) { return }

    switch get_char_at(t) {
    case '=': token.v = .ampersand_equal;     t.offset += 1
    case '&': token.v = .ampersand_ampersand; t.offset += 1
    case '~':
        token.v = .ampersand_tilde
        t.offset += 1
        if is_eof(t) { return }

        if is_char(t, '=') {
            token.v = .ampersand_tilde_equal
            t.offset += 1
        }
    }
}

parse_bang :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .operation
    token.v = .bang

    t.offset += 1
    if is_eof(t) { return }

    if is_char(t, '=') {
        token.v = .bang_equal
        t.offset += 1
    }
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

parse_dash :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .operation
    token.v = .dash

    t.offset += 1
    if is_eof(t) { return }

    switch get_char_at(t) {
    case '=': token.v = .dash_equal; t.offset += 1
    case '>': token.v = .arrow;      t.offset += 1
    case '-':
        t.offset += 1
        if is_eof(t) { return }

        if get_char_at(t) == '-' {
            token.kind = .value
            token.v = nil
        } else {
            token.kind = .invalid
        }
    case :
        next := peek_next_token(t)

        if next.kind == .number && t.whitespace_to_right {
            parse_number(t, token)
        }
    }
}

parse_directive :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .identifier

    t.offset +=1
    skip_whitespaces(t)
    if !is_alpha(t) { return }
    word := get_word_at(t)

    if v, ok := reflect.enum_from_name(Odin_Directive, temp_string("d_", word)); ok {
        token.kind = .directive
        token.v = v
    }
}

parse_equal :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .operation
    token.v = .equal

    t.offset += 1
    if is_eof(t) { return }

    if is_char(t, '=') {
        token.v = .equal_equal
    }
}

parse_identifier :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    odin_constant_values := []string{"nil", "true", "false"}

    token.kind = .identifier

    word := get_word_at(t)

    if v, ok := reflect.enum_from_name(Odin_Keyword, temp_string("k_", word)); ok {
        token.kind = .keyword
        token.v = v
    } else if v, ok := reflect.enum_from_name(Odin_Type, temp_string("t_", word)); ok {
        token.kind = .type
        token.v = v
    } else if slice.contains(odin_constant_values, word) {
        token.kind = .value
    } else {
        p1, _, p3 := get_previous_tokens(t)

        switch {
        case p1.kind == .punctuation && p1.v == .colon:
            fallthrough
        case p1.kind == .punctuation && p1.v == .bracket_r:
            fallthrough
        case p3.kind == .punctuation && p3.v == .colon &&
                p1.kind == .punctuation && p1.v == .period:
            token.kind = .type
        }
    }
}

parse_greater :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .operation
    token.v = .greater
    t.offset += 1
    if is_eof(t) { return }

    switch get_char_at(t) {
    case '=': token.v = .greater_equal; t.offset += 1
    case '>':
        token.v = .greater_greater
        t.offset += 1
        if is_eof(t) { return }
        if is_char(t, '=') {
            token.v = .greater_greater_equal
            t.offset += 1
        }
    }
}

parse_less :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .operation
    token.v = .less

    t.offset += 1
    if is_eof(t) { return }

    switch get_char_at(t) {
    case '=': token.v = .less_equal; t.offset += 1
    case '<':
        token.v = .less_less
        t.offset += 1
        if is_eof(t) { return }
        if is_char(t, '=') {
            token.v = .less_less_equal
            t.offset += 1
        }
    }
}

parse_number :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .number
    get_word_at(t)
}

parse_percent :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .operation
    token.v = .percent

    t.offset += 1
    if is_eof(t) { return }

    switch get_char_at(t) {
    case '=': token.v = .percent_equal;   t.offset += 1
    case '%':
        token.v = .percent_percent
        t.offset += 1
        if is_eof(t) { return }

        if is_char(t, '=') {
            token.v = .percent_percent_equal
            t.offset += 1
        }
    }
}

parse_pipe :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .operation
    token.v = .pipe

    t.offset += 1
    if is_eof(t) { return }

    switch get_char_at(t) {
    case '=': token.v = .pipe_equal; t.offset += 1
    case '|':
        token.v = .pipe_pipe

        t.offset += 1
        if is_eof(t) { return }

        if is_char(t, '=') {
            token.v = .pipe_pipe_equal
            t.offset += 1
        }
    }
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

parse_plus :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .operation
    token.v = .plus

    t.offset += 1
    if is_eof(t) { return }

    if is_char(t, '=') {
        token.v = .plus_equal
        t.offset += 1
    }
}

parse_slash :: proc(t: ^Odin_Tokenizer, token: ^Token) {
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

parse_star :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .operation
    token.v = .star

    t.offset += 1
    if is_eof(t) { return }

    if is_char(t, '=') {
        token.v = .star_equal
        t.offset += 1
    }
}

parse_string :: proc(t: ^Odin_Tokenizer, token: ^Token) {
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

parse_tab :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .generic
    t.offset += 1
    if !is_eof(t) && is_char(t, '\t') { t.offset += 1 }
}

parse_tilde :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .operation
    token.v = .tilde

    t.offset += 1
    if is_eof(t) { return }

    if is_char(t, '=') {
        token.v = .tilde_equal
        t.offset += 1
    }
}
