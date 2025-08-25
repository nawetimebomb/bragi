#+private file
package main

import "core:slice"
import "core:strings"

Jai_Tokenizer :: struct {
    using tokenizer: Tokenizer,

    prev_token: Token,
}

Token :: struct {
    using token: Basic_Token,
}

@(private)
tokenize_jai :: proc(buffer: ^Buffer, starting_offset := 0) {
    tokenizer: Jai_Tokenizer
    tokenizer.buf = strings.to_string(buffer.text_content)
    tokenizer.starting_offset = starting_offset

    for {
        token := get_next_token(&tokenizer)
        if token.kind == .EOF do break

        tokenizer.prev_token = token

        save_token(buffer, &tokenizer, token)
    }
}

@(private)
tokenize_jai_indentation :: proc(buffer: ^Buffer, text: string) -> []Indentation_Token {
    tokenizer: Jai_Tokenizer
    tokenizer.buf = text
    tokens := make([dynamic]Indentation_Token, context.temp_allocator)

    for {
        token := get_next_token(&tokenizer)
        indent: Indentation_Token

        #partial switch token.kind {
            case .Punctuation: {
                if punctuation, is_punctuation := token.variant.(Punctuation); is_punctuation {
                    #partial switch punctuation {
                        case .Brace_Left:    indent.action = .Open;  indent.kind = .Brace
                        case .Brace_Right:   indent.action = .Close; indent.kind = .Brace
                        case .Bracket_Left:  indent.action = .Open;  indent.kind = .Bracket
                        case .Bracket_Right: indent.action = .Close; indent.kind = .Bracket
                        case .Paren_Left:    indent.action = .Open;  indent.kind = .Paren
                        case .Paren_Right:   indent.action = .Close; indent.kind = .Paren
                    }
                }
            }
        }

        append(&tokens, indent)
        if token.kind == .EOF do break
    }

    assert(len(tokens) > 0)
    return tokens[:]
}

get_next_token :: proc(t: ^Jai_Tokenizer) -> (token: Token) {
    skip_whitespaces(t)

    token.start = t.offset
    token.kind  = .EOF
    if is_eof(t) do return

    if is_alpha(t) || is_char(t, '_') {
        parse_identifier(t, &token)
    } else if is_number(t) {
        parse_number(t, &token)
    } else {
        switch t.buf[t.offset] {
        case '*':  tokenizer_parse_asterisk(t, &token)
        case '=':  tokenizer_parse_equal   (t, &token)
        case '>':  tokenizer_parse_greater (t, &token)
        case '<':  tokenizer_parse_less    (t, &token)
        case '-':  tokenizer_parse_minus   (t, &token)
        case '|':  tokenizer_parse_pipe    (t, &token)
        case '+':  tokenizer_parse_plus    (t, &token)
        case '/':  tokenizer_parse_slash   (t, &token)
        case '\t': tokenizer_parse_tab     (t, &token)
        case '~':  tokenizer_parse_tilde   (t, &token)

        case ':':  parse_colon             (t, &token)
        case '#':  parse_directive         (t, &token)
        case '.':  parse_dot               (t, &token)
        case '@':  parse_note              (t, &token)
        case '"':  parse_string_literal    (t, &token)

        case ';':  token.kind = .Punctuation; token.variant = .Semicolon;     t.offset += 1
        case ',':  token.kind = .Punctuation; token.variant = .Comma;         t.offset += 1
        case '{':  token.kind = .Punctuation; token.variant = .Brace_Left;    t.offset += 1
        case '}':  token.kind = .Punctuation; token.variant = .Brace_Right;   t.offset += 1
        case '[':  token.kind = .Punctuation; token.variant = .Bracket_Left;  t.offset += 1
        case ']':  token.kind = .Punctuation; token.variant = .Bracket_Right; t.offset += 1
        case '(':  token.kind = .Punctuation; token.variant = .Paren_Left;    t.offset += 1
        case ')':  token.kind = .Punctuation; token.variant = .Paren_Right;   t.offset += 1
        case '$':  token.kind = .Punctuation; token.variant = .Dollar_Sign;   t.offset += 1
        case '?':  token.kind = .Operation;   token.variant = .Question;      t.offset += 1
        case '!':  token.kind = .Operation;   token.variant = .Bang;          t.offset += 1
        case '&':  token.kind = .Operation;   token.variant = .Ampersand;     t.offset += 1
        case '%':  token.kind = .Operation;   token.variant = .Percent;       t.offset += 1
        case '^':  token.kind = .Operation;   token.variant = .Caret;         t.offset += 1
        case '`':  token.kind = .Operation;   token.variant = .Backtick;      t.offset += 1
        case '\n': token.kind = .Punctuation; token.variant = .Newline;       t.offset += 1
        }
    }

    token.length = t.offset - token.start
    return
}

parse_colon :: proc(t: ^Jai_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Colon
    t.offset += 1
    if is_eof(t) do return

    switch t.buf[t.offset] {
    case ':': token.variant = .Colon_Colon; t.offset += 1
    case '=': token.variant = .Colon_Equal; t.offset += 1
    }
}

parse_directive :: proc(t: ^Jai_Tokenizer, token: ^Token) {
    token.kind = .None
    t.offset += 1
    if is_eof(t) do return

    token.text = read_word(t)
    if slice.contains(DIRECTIVES, token.text) do token.kind = .Directive
}

parse_dot :: proc(t: ^Jai_Tokenizer, token: ^Token) {
    token.kind = .Punctuation
    token.variant = .Dot
    t.offset += 1
    if is_eof(t) do return

    if is_char(t, '.') {
        token.variant = .Dot_Dot
        t.offset += 1
    } else if t.whitespace_to_left {
        next_token := peek_next_token(t)

        if next_token.kind == .Identifier {
            token.kind = .Enum_Variant
            token.variant = nil
            t.offset = next_token.start + next_token.length
        }
    }
}

parse_identifier :: proc(t: ^Jai_Tokenizer, token: ^Token) {
    token.kind = .Identifier
    token.text = read_word(t)

    // keep this order, hoping to find the value in smaller slices first.
    switch {
    case token.text == "DONE":
        if t.prev_token.kind == .Directive && t.prev_token.text == "string" {
            token.kind = .String_Raw

            for !is_eof(t) {
                word := read_word(t)
                if word == "DONE" do break
                t.offset += 1
            }
        }
    case slice.contains(CONSTANTS, token.text): token.kind = .Constant
    case slice.contains(TYPES,     token.text): token.kind = .Type
    case slice.contains(KEYWORDS,  token.text): token.kind = .Keyword
    }
}

parse_number :: proc(t: ^Jai_Tokenizer, token: ^Token) {
    is_decimal_number_continuation :: proc(t: ^Jai_Tokenizer) -> bool {
        return is_number(t) || is_char(t, '.') || is_char(t, '-') ||
            is_char(t, 'e') || is_char(t, 'E')
    }

    token.kind = .Number
    t.offset += 1
    if is_eof(t) do return

    if is_decimal_number_continuation(t) || is_char(t, '_') {
        decimal_point_found := false
        scientific_notation_found := false

        for !is_eof(t) && (is_decimal_number_continuation(t) || is_char(t, '_')) {
            if is_char(t, '.') {
                b1, ok := peek_byte(t, 1)
                if !ok do break
                if b1 == '.' do break

                if decimal_point_found do break
                decimal_point_found = true
            } else if is_char(t, 'e') || is_char(t, 'E') {
                if scientific_notation_found || !decimal_point_found do break
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

parse_note :: proc(t: ^Jai_Tokenizer, token: ^Token) {
    token.kind = .Note
    t.offset += 1
    if is_eof(t) do return

    for !is_eof(t) && is_alphanumeric(t) do t.offset += 1
}

parse_string_literal :: proc(t: ^Jai_Tokenizer, token: ^Token) {
    token.kind = .String_Literal
    escape_found := false
    t.offset += 1

    for !is_eof(t) && !is_char(t, '\n') {
        if is_char(t, '"') && !escape_found do break
        escape_found = !escape_found && is_char(t, '\\')
        t.offset += 1
    }

    if is_eof(t) do return
    t.offset += 1
}

peek_next_token :: proc(t: ^Jai_Tokenizer, eat_whitespace := true) -> (next_token: Token) {
    t_copy := t^
    if eat_whitespace do skip_whitespaces(&t_copy)
    next_token = get_next_token(&t_copy)
    return
}

CONSTANTS :: []string{
    "context", "it", "it_index", "null", "true", "false", "temp",
}

DIRECTIVES :: []string{
    "add_context", "align", "as", "asm", "assert", "bake_arguments", "bake_constants", "bytes",
    "c_call", "caller_code", "caller_location", "char", "code", "compiler", "complete", "cpp_method",
    "cpp_return_type_is_non_pod", "deprecated", "dump", "dynamic_specialize", "elsewhere", "expand",
    "file", "filepath", "foreign", "library", "system_library", "if", "ifx", "import", "insert",
    "insert_internal", "intrinsic", "line", "load", "location", "modify", "module_parameters", "must",
    "no_abc", "no_aoc", "no_alias", "no_context", "no_padding", "no_reset", "place", "placeholder",
    "poke_name", "procedure_of_call", "program_export", "run", "runtime_support", "scope_export",
    "scope_file", "scope_module", "specified", "string", "symmetric", "this", "through", "type",
    "type_info_no_size_complaint", "type_info_none", "type_info_procedures_are_void_pointers",
    "compile_time", "no_debug", "procedure_name", "discard", "entry_point", "Context",
}

KEYWORDS :: []string{
    "break", "case", "cast", "code_of", "continue", "defer", "else", "enum", "enum_flags", "for",
    "initializer_of", "if", "ifx", "is_constant", "inline", "push_context", "return", "size_of",
    "struct", "then", "type_info", "type_of", "union", "using", "while", "xx", "operator", "remove",
    "interface", "no_inline",
}

TYPES :: []string{
    "__reg", "bool", "float", "float32", "float64", "int", "reg", "s16", "s32", "s64", "s8", "string",
    "u16", "u32", "u64", "u8", "void", "v128", "Any", "Code", "Type",
}
