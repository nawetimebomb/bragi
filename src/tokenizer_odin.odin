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
    Ampersand, Ampersand_Ampersand, Ampersand_Equal, Ampersand_Tilde, Ampersand_Tilde_Equal,
    Asterisk, Asterisk_Equal, Bang, Bang_Equal, Colon, Colon_Colon, Colon_Equal,
    Equal, Equal_Equal, Minus, Minus_Equal, Plus, Plus_Equal, Slash, Slash_Equal,
    Greater, Greater_Equal, Greater_Greater, Greater_Greater_Equal,
    Less, Less_Equal, Less_Less, Less_Less_Equal, Dot_Dot_Equal, Dot_Dot_Less,
    Percent, Percent_Equal, Percent_Percent, Percent_Percent_Equal,
    Pipe, Pipe_Equal, Pipe_Pipe, Pipe_Pipe_Equal, Tilde, Tilde_Equal,
}

Punctuation :: enum {
    Brace_Left,   Brace_Right,
    Bracket_Left, Bracket_Right,
    Paren_Left,   Paren_Right,
    Dot, Dot_Dot,

    At, Caret, Dollar_Sign, Comma,
    Question, Newline, Semicolon, Tab,
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
            punctuation, is_punctuation := t1.variant.(Punctuation)
            op, is_op := t1.variant.(Operation)

            if is_punctuation && punctuation == .Caret {
                // a pointer type
                t1.kind = .Type
                token.kind = .Type
                save_token(buffer, &tokenizer, t1)
            } else if is_op && op == .Colon && t2.kind == .Identifier {
                token.kind = .Type
            }
        case should_save_proc_name(&tokenizer, token):
            if t1.kind == .Directive { // like #force_inline
                t3.kind = .Function
                save_token(buffer, &tokenizer, t3)
            } else if t1.kind == .Operation { // name :: proc
                if op, ok := t1.variant.(Operation); ok && op == .Colon_Colon {
                    t2.kind = .Function
                    save_token(buffer, &tokenizer, t2)
                }
            } else {
                if punctuation, ok := token.variant.(Punctuation); ok && punctuation == .Paren_Left {
                    t1.kind = .Function
                    save_token(buffer, &tokenizer, t1)
                }
            }
        case should_save_struct_name(&tokenizer, token):
            t2.kind = .Type
            save_token(buffer, &tokenizer, t2)
        case should_save_variable_name(&tokenizer, token):
            if t2.kind != .Type {
                t2.kind = .Variable
                save_token(buffer, &tokenizer, t2)
            }
        }

        tokenizer.prev_tokens[2] = tokenizer.prev_tokens[1]
        tokenizer.prev_tokens[1] = tokenizer.prev_tokens[0]
        tokenizer.prev_tokens[0] = token

        save_token(buffer, &tokenizer, token)
    }
}

@(private)
tokenize_odin_indentation :: proc(buffer: ^Buffer, text: string) -> []Indentation_Token {
    tokenizer: Odin_Tokenizer
    tokenizer.buf = text
    tokens := make([dynamic]Indentation_Token, context.temp_allocator)

    for {
        token := get_next_token(&tokenizer)
        indent: Indentation_Token

        // TODO(nawe) handle the raw string and the comment multiline
        // that shouldn't really start with indentation.
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
        case '!':  parse_bang          (t, &token)
        case '#':  parse_directive     (t, &token)
        case '%':  parse_percent       (t, &token)
        case '&':  parse_ampersand     (t, &token)
        case '*':  parse_asterisk      (t, &token)
        case '+':  parse_plus          (t, &token)
        case '-':  parse_minus         (t, &token)
        case ':':  parse_colon         (t, &token)
        case '<':  parse_less          (t, &token)
        case '=':  parse_equal         (t, &token)
        case '>':  parse_greater       (t, &token)
        case '|':  parse_pipe          (t, &token)
        case '~':  parse_tilde         (t, &token)
        case '/':  parse_slash         (t, &token)
        case '.':  parse_dot           (t, &token)
        case '\t': parse_tab           (t, &token)

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

parse_ampersand :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Ampersand
    t.offset += 1
    if is_eof(t) do return

    switch {
    case is_char(t, '='):
        token.variant = .Ampersand_Equal
        t.offset += 1
    case is_char(t, '&'):
        token.variant = .Ampersand_Ampersand
        t.offset += 1
    case is_char(t, '~'):
        token.variant = .Ampersand_Tilde
        t.offset += 1
        if is_eof(t) do return

        if is_char(t, '=') {
            token.variant = .Ampersand_Tilde_Equal
            t.offset += 1
        }
    }
}

parse_asterisk :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Asterisk
    t.offset += 1
    if is_eof(t) do return

    if is_char(t, '=') {
        token.variant = .Asterisk_Equal
        t.offset += 1
    }
}

parse_bang :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Bang
    t.offset += 1
    if is_eof(t) do return

    if is_char(t, '=') {
        token.variant = .Bang_Equal
        t.offset += 1
    }
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

parse_dot :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Punctuation
    token.variant = .Dot
    t.offset += 1
    if is_eof(t) do return

    switch {
    case is_char(t, '?'):
        token.kind = .Builtin_Function
    case is_char(t, '.'):
        token.variant = .Dot_Dot
        t.offset += 1
        if is_eof(t) do return

        switch {
        case is_char(t, '='):
            token.variant = .Dot_Dot_Equal
            t.offset += 1
        case is_char(t, '<'):
            token.variant = .Dot_Dot_Less
            t.offset += 1
        }
    case :
        // check for enum variant
        p1, _, _ := get_previous_tokens(t)

        if p1.kind != .Identifier && t.whitespace_to_left {
            next_token := peek_next_token(t)
            if next_token.kind == .Identifier {
                token.kind = .Enum_Variant
                t.offset = next_token.start + next_token.length
            }
        }
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

parse_greater :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Greater
    t.offset += 1
    if is_eof(t) do return

    switch {
    case is_char(t, '='):
        token.variant = .Greater_Equal
        t.offset += 1
    case is_char(t, '>'):
        token.variant = .Greater_Greater
        t.offset += 1

        if is_char(t, '=') {
            token.variant = .Greater_Greater_Equal
            t.offset += 1
        }
    }
}

parse_identifier :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Identifier
    token.text = read_word(t)

    switch {
    case slice.contains(CONSTANTS,  token.text): token.kind = .Constant
    case slice.contains(KEYWORDS,   token.text): token.kind = .Keyword
    case slice.contains(TYPES,      token.text): token.kind = .Type
    case slice.contains(BUILTINS,   token.text): token.kind = .Builtin_Function
    }
}

parse_less :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Less
    t.offset += 1
    if is_eof(t) do return

    switch {
    case is_char(t, '='):
        token.variant = .Less_Equal
        t.offset += 1
    case is_char(t, '<'):
        token.variant = .Less_Less
        t.offset += 1
        if is_char(t, '=') {
            token.variant = .Less_Less_Equal
            t.offset += 1
        }
    }
}

parse_minus :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Minus
    t.offset += 1
    if is_eof(t) do return

    if is_char(t, '=') {
        token.variant = .Minus_Equal
        t.offset +=1
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

parse_percent :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Percent

    t.offset += 1
    if is_eof(t) do return

    switch {
    case is_char(t, '='): token.variant = .Percent_Equal; t.offset += 1
    case is_char(t, '%'):
        token.variant = .Percent_Percent
        t.offset += 1
        if is_eof(t) do return

        if is_char(t, '=') {
            token.variant = .Percent_Percent_Equal
            t.offset += 1
        }
    }
}

parse_pipe :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Pipe
    t.offset += 1
    if is_eof(t) do return

    switch {
    case is_char(t, '='):
        token.variant = .Pipe_Equal
        t.offset += 1
    case is_char(t, '|'):
        token.variant = .Pipe_Pipe
        t.offset += 1

        if is_char(t, '=') {
            token.variant = .Pipe_Pipe_Equal
            t.offset += 1
        }
    }
}

parse_plus :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Plus
    t.offset += 1
    if is_eof(t) do return

    if is_char(t, '=') {
        token.variant = .Plus_Equal
        t.offset += 1
    }
}

parse_slash :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Slash
    t.offset += 1
    if is_eof(t) do return

    switch {
    case is_char(t, '='):
        token.variant = .Slash_Equal
        t.offset += 1
    case is_char(t, '/'):
        token.kind = .Comment
        token.variant = nil
        t.offset += 1
        for !is_eof(t) && !is_char(t, '\n') do t.offset += 1
    case is_char(t, '*'):
        token.kind = .Comment_Multiline
        token.variant = nil
        t.offset += 1
        comments_block_count := 0

        for !is_eof(t) {
            if is_char(t, '*') {
                if b, ok := peek_byte(t, 1); ok && b == '/' {
                    if comments_block_count == 0 {
                        t.offset += 2
                        break
                    } else {
                        comments_block_count -= 1
                    }
                }
            } else if is_char(t, '/') {
                if b, ok := peek_byte(t, 1); ok && b == '*' {
                    comments_block_count += 1
                    t.offset += 1
                }
            }

            t.offset += 1
        }
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

parse_tab :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Punctuation
    token.variant = .Tab
    t.offset += 1
    for !is_eof(t) && is_char(t, '\t') do t.offset += 1
}

parse_tilde :: proc(t: ^Odin_Tokenizer, token: ^Token) {
    token.kind = .Operation
    token.variant = .Tilde
    t.offset += 1
    if is_eof(t) do return

    if is_char(t, '=') {
        token.variant = .Tilde_Equal
        t.offset += 1
    }
}

get_previous_tokens :: proc(t: ^Odin_Tokenizer) -> (t1, t2, t3: Token) {
    return t.prev_tokens[0], t.prev_tokens[1], t.prev_tokens[2]
}

peek_next_token :: proc(t: ^Odin_Tokenizer, eat_whitespace := true) -> (next_token: Token) {
    t_copy := t^
    if eat_whitespace do skip_whitespaces(&t_copy)
    next_token = get_next_token(&t_copy)
    return next_token
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

should_save_proc_name :: proc(t: ^Odin_Tokenizer, token: Token) -> bool {
    if token.kind == .Keyword {
        return token.text == "proc"
    } else if token.kind == .Punctuation {
        t1, _, _ := get_previous_tokens(t)
        punctuation, is_punctuation := token.variant.(Punctuation)
        return t1.kind == .Identifier && is_punctuation && punctuation == .Paren_Left
    }

    return false
}

should_save_struct_name :: proc(t: ^Odin_Tokenizer, token: Token) -> bool {
    if token.kind == .Keyword && token.text == "struct" {
        t1, _, _ := get_previous_tokens(t)
        if op, is_op := t1.variant.(Operation); is_op {
            return op == .Colon_Colon
        }
    }

    return false
}

should_save_variable_name :: proc(t: ^Odin_Tokenizer, token: Token) -> bool {
    if token.kind != .Keyword {
        t1, _, t3 := get_previous_tokens(t)

        if t1.kind == .Operation {
            op := t1.variant.(Operation)
            return op == .Colon_Colon || op == .Colon_Equal ||
                (op == .Colon && t3.kind != .Keyword) // Like: case <value>:
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

BUILTINS :: []string{
    "abs_complex128", "abs_complex32", "abs_complex64",
    "abs_quaternion128", "abs_quaternion256", "abs_quaternion64",
    "add_thread_local_cleaner", "aeabi_d2h", "align_forward_int",
    "align_forward_uint", "align_forward_uintptr",
    "alloc_from_memory_block", "append_elem", "append_elem_string",
    "append_elems", "append_nothing", "append_soa_elem",
    "append_soa_elems", "append_string", "arena_alloc", "arena_allocator",
    "arena_allocator_proc", "arena_check_temp", "arena_destroy",
    "arena_free_all", "arena_init", "arena_temp_begin", "arena_temp_end",
    "arena_temp_ignore", "assert", "assert_contextless", "assign_at_elem",
    "assign_at_elem_string", "assign_at_elems", "bounds_check_error",
    "bounds_check_error_loc", "bounds_trap", "card",
    "clear_dynamic_array", "clear_map", "clear_soa_dynamic_array",
    "complex128_eq", "complex128_ne", "complex32_eq", "complex32_ne",
    "complex64_eq", "complex64_ne", "container_of", "copy_from_string",
    "copy_from_string16", "copy_slice", "cstring16_cmp", "cstring16_eq",
    "cstring16_ge", "cstring16_gt", "cstring16_le", "cstring16_len",
    "cstring16_lt", "cstring16_ne", "cstring16_to_string16",
    "cstring_cmp", "cstring_eq", "cstring_ge", "cstring_gt", "cstring_le",
    "cstring_len", "cstring_lt", "cstring_ne", "cstring_to_string",
    "debug_trap", "default_allocator", "default_allocator_proc",
    "default_assertion_contextless_failure_proc",
    "default_assertion_failure_proc", "default_context", "default_hasher",
    "default_hasher_complex128", "default_hasher_cstring",
    "default_hasher_f64", "default_hasher_quaternion256",
    "default_hasher_string", "default_logger", "default_logger_proc",
    "default_random_generator", "default_random_generator_proc",
    "default_temp_allocator", "default_temp_allocator_destroy",
    "default_temp_allocator_init", "default_temp_allocator_proc",
    "default_temp_allocator_temp_begin",
    "default_temp_allocator_temp_end", "delete_cstring",
    "delete_cstring16", "delete_dynamic_array", "delete_key",
    "delete_map", "delete_slice", "delete_soa_slice", "delete_string",
    "delete_string16", "divmodti4", "divti3", "dynamic_array_expr_error",
    "dynamic_array_expr_error_loc", "encode_rune", "ensure",
    "ensure_contextless", "extendhfsf2", "fixdfti", "fixunsdfdi",
    "fixunsdfti", "floattidf", "floattidf_unsigned", "gnu_f2h_ieee",
    "gnu_h2f_ieee", "heap_alloc", "heap_allocator", "heap_allocator_proc",
    "heap_free", "heap_resize", "init_global_temporary_allocator",
    "inject_at_elem", "inject_at_elem_string", "inject_at_elems",
    "into_dynamic_soa", "is_power_of_two_int", "is_power_of_two_uint",
    "is_power_of_two_uintptr", "make_aligned", "make_dynamic_array",
    "make_dynamic_array_error_loc", "make_dynamic_array_len",
    "make_dynamic_array_len_cap", "make_map", "make_map_cap",
    "make_map_expr_error_loc", "make_multi_pointer", "make_slice",
    "make_slice_error_loc", "make_soa_aligned", "make_soa_dynamic_array",
    "make_soa_dynamic_array_len", "make_soa_dynamic_array_len_cap",
    "make_soa_slice", "map_alloc_dynamic", "map_cap",
    "map_cell_index_dynamic", "map_cell_index_dynamic_const",
    "map_cell_index_static", "map_cell_info", "map_clear_dynamic",
    "map_data", "map_desired_position", "map_entry", "map_erase_dynamic",
    "map_exists_dynamic", "map_free_dynamic", "map_get",
    "map_grow_dynamic", "map_hash_is_deleted", "map_hash_is_empty",
    "map_hash_is_valid", "map_info", "map_insert",
    "map_insert_hash_dynamic", "map_insert_hash_dynamic_with_key",
    "map_kvh_data_dynamic", "map_kvh_data_static",
    "map_kvh_data_values_dynamic", "map_len", "map_load_factor",
    "map_log2_cap", "map_lookup_dynamic", "map_probe_distance",
    "map_reserve_dynamic", "map_resize_threshold", "map_seed",
    "map_seed_from_map_data", "map_shrink_dynamic",
    "map_total_allocation_size", "map_total_allocation_size_from_value",
    "map_upsert", "matrix_bounds_check_error", "mem_alloc",
    "mem_alloc_bytes", "mem_alloc_non_zeroed", "mem_copy",
    "mem_copy_non_overlapping", "mem_free", "mem_free_all",
    "mem_free_bytes", "mem_free_with_size", "mem_resize", "mem_zero",
    "memory_block_alloc", "memory_block_dealloc", "memory_compare",
    "memory_compare_zero", "memory_equal", "memory_prefix_length",
    "memset", "modti3", "mul_quaternion128", "mul_quaternion256",
    "mul_quaternion64", "multi_pointer_slice_expr_error",
    "multi_pointer_slice_handle_error", "new", "new_aligned", "new_clone",
    "nil_allocator", "nil_allocator_proc", "non_zero_append_elem",
    "non_zero_append_elem_string", "non_zero_append_elems",
    "non_zero_append_soa_elem", "non_zero_append_soa_elems",
    "non_zero_mem_resize", "non_zero_reserve_dynamic_array",
    "non_zero_reserve_soa", "non_zero_resize_dynamic_array",
    "non_zero_resize_soa", "ordered_remove", "ordered_remove_soa",
    "panic", "panic_allocator", "panic_allocator_proc",
    "panic_contextless", "pop", "pop_front", "pop_front_safe", "pop_safe",
    "print_any_single", "print_byte", "print_caller_location",
    "print_encoded_rune", "print_i64", "print_int", "print_rune",
    "print_string", "print_strings", "print_type", "print_typeid",
    "print_u64", "print_uint", "print_uintptr", "println_any",
    "quaternion128_eq", "quaternion128_ne", "quaternion256_eq",
    "quaternion256_ne", "quaternion64_eq", "quaternion64_ne",
    "quo_complex128", "quo_complex32", "quo_complex64",
    "quo_quaternion128", "quo_quaternion256", "quo_quaternion64",
    "random_generator_query_info", "random_generator_read_bytes",
    "random_generator_read_ptr", "random_generator_reset_bytes",
    "random_generator_reset_u64", "raw_soa_footer_dynamic_array",
    "raw_soa_footer_slice", "read_cycle_counter", "remove_range",
    "reserve_map", "reserve_soa", "resize_dynamic_array", "resize_soa",
    "run_thread_local_cleaners", "shrink_dynamic_array", "shrink_map",
    "slice_expr_error_hi", "slice_expr_error_hi_loc",
    "slice_expr_error_lo_hi", "slice_expr_error_lo_hi_loc",
    "slice_handle_error", "stderr_write", "string16_cmp",
    "string16_decode_last_rune", "string16_decode_rune", "string16_eq",
    "string16_ge", "string16_gt", "string16_le", "string16_lt",
    "string16_ne", "string_cmp", "string_decode_last_rune",
    "string_decode_rune", "string_eq", "string_ge", "string_gt",
    "string_le", "string_lt", "string_ne", "trap", "truncdfhf2",
    "truncsfhf2", "type_assertion_check", "type_assertion_check2",
    "type_assertion_trap", "type_info_base",
    "type_info_base_without_enum", "type_info_core", "typeid_base",
    "typeid_base_without_enum", "typeid_core", "udivmod128", "udivmodti4",
    "udivti3", "umodti3", "unimplemented", "unimplemented_contextless",
    "unordered_remove", "align_forward", "append", "append_soa",
    "assign_at", "clear", "clear_soa", "copy", "delete", "delete_soa",
    "free", "free_all", "inject_at", "is_power_of_two", "make",
    "make_soa", "non_zero_append", "non_zero_reserve", "non_zero_resize",
    "raw_soa_footer", "reserve", "resize", "shrink",
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

TYPES :: []string{
    "bool", "b8", "b16", "b32", "b64",
    "int",  "i8", "i16", "i32", "i64", "i128",
    "uint", "u8", "u16", "u32", "u64", "u128", "uintptr",
    "byte",
    "i16le", "i32le", "i64le", "i128le", "u16le", "u32le", "u64le", "u128le",
    "i16be", "i32be", "i64be", "i128be", "u16be", "u32be", "u64be", "u128be",
    "f16", "f32", "f64",
    "f16le", "f32le", "f64le",
    "f16be", "f32be", "f64be",
    "complex32", "complex64", "complex128",
    "quaternion64", "quaternion128", "quaternion256",
    "rune",
    "string", "cstring",
    "rawptr",
    "typeid", "any",
    "matrix",
    "map",
    "bit_set",
    "Maybe",
}
