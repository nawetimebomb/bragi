#+private="file"
package main

import "core:slice"
import "core:strings"

Odin_Tokenizer :: struct {
    using tokenizer: Tokenizer,

    prev_tokens: [3]Token,
}

Token :: struct {
    using token: Basic_Token,

    variant: union {
        Operation,
        Punctuation,
    },
}

Operation :: enum {
    Colon, Colon_Colon, Colon_Equal,
    Equal, Equal_Equal,
}

Punctuation :: enum {
    Brace_Left,   Brace_Right,
    Bracket_Left, Bracket_Right,
    Paren_Left,   Paren_Right,
    At, Caret, Dollar_Sign, Comma,
    Question, Newline, Semicolon,
}

@(private)
tokenize_odin :: proc(buffer: ^Buffer, starting_offset := 0) {
    tokenizer: Odin_Tokenizer
    tokenizer.buf = strings.to_string(buffer.text_content)
    tokenizer.starting_offset = starting_offset

    for {
        token := get_next_token(&tokenizer)
        if token.kind == .EOF do break

        t1, t2, t3 := get_previous_tokens(&tokenizer)

        switch {
        case should_save_current_token_like_directive(&tokenizer, token):
            token.kind = .Directive
        case should_save_current_token_like_type(&tokenizer, token):
            // a pointer type
            t1.kind = .Type
            token.kind = .Type
            save_token(buffer, &tokenizer, t1)
        case should_save_proc_name_token(&tokenizer, token):
            if t1.kind == .Directive { // like #force_inline
                t3.kind = .Function
                save_token(buffer, &tokenizer, t3)
            } else {
                t2.kind = .Function
                save_token(buffer, &tokenizer, t2)
            }
        case should_save_struct_name(&tokenizer, token):
            t2.kind = .Type
            save_token(buffer, &tokenizer, t2)
        case should_save_variable_name(&tokenizer, token):
            t2.kind = .Variable
            save_token(buffer, &tokenizer, t2)
        }

        tokenizer.prev_tokens[2] = tokenizer.prev_tokens[1]
        tokenizer.prev_tokens[1] = tokenizer.prev_tokens[0]
        tokenizer.prev_tokens[0] = token

        save_token(buffer, &tokenizer, token)
    }
}

get_next_token :: proc(t: ^Odin_Tokenizer) -> (token: Token) {
    skip_whitespaces(t)

    token.start = t.offset
    token.kind = .EOF
    if is_eof(t) do return

    if is_alpha(t) || is_char(t, '_') {
        parse_identifier(t, &token)
    } else if is_number(t) {
        parse_number(t, &token)
    } else {
        switch t.buf[t.offset] {
        case ':':  parse_colon         (t, &token)
        case '=':  parse_equal         (t, &token)
        case '#':  parse_directive     (t, &token)
        case '\'': fallthrough
        case '"':  fallthrough
        case '`':  parse_string_literal(t, &token)

        case ';':  token.kind = .Punctuation; token.variant = .Semicolon;     t.offset += 1
        case ',':  token.kind = .Punctuation; token.variant = .Comma;         t.offset += 1
        case '^':  token.kind = .Punctuation; token.variant = .Caret;         t.offset += 1
        case '?':  token.kind = .Punctuation; token.variant = .Question;      t.offset += 1
        case '{':  token.kind = .Punctuation; token.variant = .Brace_Left;    t.offset += 1
        case '}':  token.kind = .Punctuation; token.variant = .Brace_Right;   t.offset += 1
        case '[':  token.kind = .Punctuation; token.variant = .Bracket_Left;  t.offset += 1
        case ']':  token.kind = .Punctuation; token.variant = .Bracket_Right; t.offset += 1
        case '(':  token.kind = .Punctuation; token.variant = .Paren_Left;    t.offset += 1
        case ')':  token.kind = .Punctuation; token.variant = .Paren_Right;   t.offset += 1
        case '$':  token.kind = .Punctuation; token.variant = .Dollar_Sign;   t.offset += 1
        case '@':  token.kind = .Punctuation; token.variant = .At;            t.offset += 1
        case '\n': token.kind = .Punctuation; token.variant = .Newline;       t.offset += 1
        }
    }

    token.length = t.offset - token.start

    return
}

parse_colon :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Colon
    t.offset += 1
    if is_eof(t) do return

    switch t.buf[t.offset] {
    case ':': token.variant = .Colon_Colon; t.offset += 1
    case '=': token.variant = .Colon_Equal; t.offset += 1
    }
}

parse_equal :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Equal
    t.offset += 1
    if is_eof(t) do return

    if is_char(t, '=') {
        token.variant = .Equal_Equal
        t.offset += 1
    }
}

parse_directive :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .None
    t.offset += 1
    if is_eof(t) do return

    // maybe global directives like #+private
    if is_char(t, '+') {
        t.offset += 1
    }
    if is_eof(t) do return

    token.text = read_word(t)
    if slice.contains(ATTRIBUTES, token.text) do token.kind = .Directive
    if slice.contains(DIRECTIVES, token.text) do token.kind = .Directive
}

parse_identifier :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Identifier
    token.text = read_word(t)

    switch {
    case slice.contains(CONSTANTS,  token.text): token.kind = .Constant
    case slice.contains(KEYWORDS,   token.text): token.kind = .Keyword
    }
}

parse_number :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    is_decimal_number_continuation :: proc(t: ^Odin_Tokenizer) -> bool {
        return is_number(t) || is_char(t, '.') || is_char(t, '-') ||
            is_char(t, 'e') || is_char(t, 'E') || is_char(t, 'i') ||
            is_char(t, 'j') || is_char(t, 'k')
    }

    token.kind = .Number
    t.offset += 1
    if is_eof(t) do return

    if is_decimal_number_continuation(t) || is_char(t, '_') {
        decimal_point_found := false
        scientific_notation_found := false

        for !is_eof(t) && (is_decimal_number_continuation(t) || is_char(t, '_')) {
            if is_char(t, '.') {
                // break early for range operation (..< or ..=)
                b1, b2: byte
                ok: bool

                b1, ok = peek_byte(t, 1)
                if !ok do break

                if b1 == '.' {
                    b2, ok = peek_byte(t, 2)
                    if !ok do break

                    if b2 == '<' || b2 == '=' {
                        break
                    }

                }

                if decimal_point_found do break
                decimal_point_found = true
            } else if is_char(t, 'i') || is_char(t, 'j') || is_char(t, 'k') {
                // imaginary or quaternion
                t.offset += 1
                break
            } else if is_char(t, 'e') || is_char(t, 'E') {
                if scientific_notation_found do break
                scientific_notation_found = true
            } else if is_char(t, '-') {
                // negative exponent in scientific notation
                if !scientific_notation_found do break
                prev_byte, _ := peek_byte(t, -1)
                if prev_byte != 'e' || prev_byte != 'E' do break
            }

            t.offset += 1
        }
    } else if is_hex_prefix(t) {
        t.offset += 1
        for !is_eof(t) && (is_hex(t) || is_char(t, '_')) do t.offset += 1
    } else if is_char(t, 'o') {
        t.offset += 1
        for !is_eof(t) && (is_octal(t) || is_char(t, '_')) do t.offset += 1
    } else if is_char(t, 'b') {
        t.offset += 1
        for !is_eof(t) && (is_char(t, '0') || is_char(t, '1') || is_char(t, '_')) do t.offset += 1
    }
}

parse_string_literal :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    delimiter := t.buf[t.offset]

    if delimiter == '`' {
        token.kind = .String_Raw
        t.offset += 1
        for !is_eof(t) && !is_char(t, '`') do t.offset += 1
    } else {
        token.kind = .String_Literal
        escape_found := false

        t.offset += 1
        for !is_eof(t) && !is_char(t, '\n') {
            if is_char(t, delimiter) && !escape_found do break
            escape_found = !escape_found && is_char(t, '\\')
            t.offset += 1
        }
    }

    if is_eof(t) do return
    t.offset += 1
}

get_previous_tokens :: proc(t: ^Odin_Tokenizer) -> (t1, t2, t3: Token) {
    return t.prev_tokens[0], t.prev_tokens[1], t.prev_tokens[2]
}

should_save_current_token_like_directive :: proc(t: ^Odin_Tokenizer, token: Token) -> bool {
    if token.kind == .Identifier && slice.contains(ATTRIBUTES, token.text) {
        t1, t2, _ := get_previous_tokens(t)
        v1, ok1 := t1.variant.(Punctuation)
        v2, ok2 := t2.variant.(Punctuation)
        return (ok1 && v1 == .At) || (ok2 && v2 == .At)
    }
    return false
}

should_save_current_token_like_type :: proc(t: ^Odin_Tokenizer, token: Token) -> bool {
    t1, _, _ := get_previous_tokens(t)
    punctuation, ok := t1.variant.(Punctuation)
    return token.kind == .Identifier && ok && punctuation == .Caret
}

should_save_proc_name_token :: proc(t: ^Odin_Tokenizer, token: Token) -> bool {
    if token.kind == .Keyword do return token.text == "proc"
    return false
}

should_save_struct_name :: proc(t: ^Odin_Tokenizer, token: Token) -> bool {
    if token.kind == .Keyword && token.text == "struct" {
        t1, _, _ := get_previous_tokens(t)
        if op, ok := t1.variant.(Operation); ok do return op == .Colon_Colon
    }

    return false
}

should_save_variable_name :: proc(t: ^Odin_Tokenizer, token: Token) -> bool {
    any_string := token.kind == .String_Literal || token.kind == .String_Raw

    if any_string || token.kind == .Constant || token.kind == .Number {
        t1, _, _ := get_previous_tokens(t)
        if op, ok := t1.variant.(Operation); ok {
            return op == .Colon_Colon || op == .Colon_Equal
        }
    }
    return false
}

ATTRIBUTES :: []string{
    "private", "builtin", "test", "require_results", "export", "require",
    "entry_point_only", "link_name", "link_prefix", "link_suffix", "link_section",
    "linkage", "extra_linker_flags", "default_calling_convention", "priority_index",
    "deferred_none", "deferred_in", "deferred_out", "deferred_in_out", "deferred_in_by_ptr",
    "deferred_out_by_ptr", "deferred_in_out_by_ptr", "deprecated", "warning", "disabled", "cold",
    "init", "fini", "optimization_mode", "static", "thread_local", "rodata", "objc_name",
    "objc_class", "objc_type", "objc_is_class_method", "enable_target_feature", "require_target_feature",
    "instrumentation_enter", "instrumentation_exit", "no_instrumentation",
}

CONSTANTS :: []string{
    "context", "false", "nil", "true",
}

DIRECTIVES :: []string{
    "packed", "sparse", "raw_union", "align", "shared_nil", "no_nil", "type", "subtype",
    "partial", "unroll", "reverse", "no_alias", "any_int", "c_vararg", "by_ptr", "const",
    "optional_ok", "optional_allocator_error", "bounds_check", "no_bounds_check",
    "force_inline", "no_force_inline", "assert", "panic", "config", "defined", "exists",
    "location", "caller_location", "file", "line", "procedure", "directory", "hash",
    "load", "load_or", "load_directory", "load_hash", "soa", "relative", "simd",
}

KEYWORDS :: []string{
    "align_of", "asm", "auto_cast", "break", "case", "cast", "container_of", "continue", "defer",
    "distinct", "do", "dynamic", "else", "enum", "fallthrough", "for", "foreign", "if", "in",
    "import", "not_in", "offset_of", "or_else", "or_return", "or_break", "or_continue", "package",
    "proc", "return", "size_of", "struct", "switch", "transmute", "typeid_of", "type_info_of",
    "type_of", "union", "using", "when", "where",
}
