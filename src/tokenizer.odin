package main

Token_Kind :: enum u8 {
    None = 0,
    EOF,
    Invalid,
    Error,

    String_Literal,
    String_Raw, // maybe multiline

    Comment,
    Comment_Multiline,

    Identifier,
    Operation,
    Punctuation,

    Constant,
    Decorator,
    Directive,
    Enum_Variant,
    Function,
    Keyword,
    Note,
    Number,
    Type,
    Variable,

    Builtin_Function,
    Builtin_Variable,

    Bragi_Header1,
    Bragi_Header2,
    Bragi_Header3,
    Bragi_Header4,
    Bragi_Header5,
}

Operation :: enum {
    Ampersand, Ampersand_Ampersand, Ampersand_Equal, Ampersand_Tilde, Ampersand_Tilde_Equal,
    Asterisk, Asterisk_Equal, Bang, Bang_Equal, Colon, Colon_Colon, Colon_Equal,
    Equal, Equal_Equal, Minus, Minus_Equal, Minus_Greater, Plus, Plus_Equal, Slash, Slash_Equal,
    Greater, Greater_Equal, Greater_Greater, Greater_Greater_Equal, Backtick,
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

Basic_Token :: struct {
    kind: Token_Kind,
    start, length: int,
    text: string,

    variant: union {
        Operation,
        Punctuation,
    },
}

Indentation_Token :: struct {
    action: enum u8 {
        None, // ensure we at least register one token
        Close,
        Open,
    },
    kind: enum u8 {
        Brace,
        Bracket,
        Paren,
    },
}

Tokenizer :: struct {
    starting_offset: int,
    buf: string,
    offset: int,
    whitespace_to_left: bool,
}

tokenize_buffer :: proc(buffer: ^Buffer) {
    switch buffer.major_mode {
    case .Bragi:
    case .Jai:   tokenize_jai(buffer)
    case .Odin:  tokenize_odin(buffer)
    }

    // add the EOF token so we always have tokens.
    assign_at(&buffer.tokens, buffer.length_of_buffer + 1, Token_Kind.EOF)
}

get_indentation_tokens :: proc(buffer: ^Buffer, text: string) -> []Indentation_Token {
    switch buffer.major_mode {
    case .Bragi: return {}
    case .Jai:   return tokenize_jai_indentation (buffer, text)
    case .Odin:  return tokenize_odin_indentation(buffer, text)
    }

    unreachable()
}

save_token :: proc(buffer: ^Buffer, t: ^Tokenizer, token: Basic_Token) {
    start := t.starting_offset + token.start
    end := start + token.length
    for index in start..<end do assign_at(&buffer.tokens, index, token.kind)
}

skip_whitespaces :: proc(t: ^Tokenizer) {
    old_offset := t.offset
    for !is_eof(t) && is_whitespace(t) { t.offset += 1 }
    t.whitespace_to_left = t.offset != old_offset
}

peek_byte :: proc(t: ^Tokenizer, index_offset: int) -> (b: byte, ok: bool) {
    if t.offset + index_offset < len(t.buf) do return t.buf[t.offset + index_offset], true
    return 0, false
}

read_word :: proc(t: ^Tokenizer) -> string {
    start := t.offset
    for !is_eof(t) && is_valid_word_component(t) do t.offset += 1
    end := t.offset
    return t.buf[start:end]
}

is_alpha :: proc(t: ^Tokenizer) -> bool {
    return is_alpha_lowercase(t) || is_alpha_uppercase(t)
}

is_alphanumeric :: proc(t: ^Tokenizer) -> bool {
    return is_alpha(t) || is_number(t)
}

is_alpha_lowercase :: proc(t: ^Tokenizer) -> bool {
    b := t.buf[t.offset]
    return b >= 'a' && b <= 'z'
}

is_alpha_uppercase :: proc(t: ^Tokenizer) -> bool {
    b := t.buf[t.offset]
    return b >= 'A' && b <= 'Z'
}

is_char :: proc(t: ^Tokenizer, b: byte) -> bool {
    return !is_eof(t) && t.buf[t.offset] == b
}

is_eof :: proc(t: ^Tokenizer) -> bool {
    return t.offset >= len(t.buf)
}

is_hex_prefix :: proc(t: ^Tokenizer) -> bool {
    return is_char(t, 'h') || is_char(t, 'x')
}

is_hex :: proc(t: ^Tokenizer) -> bool {
    b := t.buf[t.offset]
    return is_number(t) || (b >= 'a' && b <= 'f') || (b >= 'A' && b <= 'F')
}

is_newline :: proc(t: ^Tokenizer) -> bool {
    return t.buf[t.offset] == '\n'
}

is_number :: proc(t: ^Tokenizer) -> bool {
    b := t.buf[t.offset]
    return b >= '0' && b <= '9'
}

is_octal :: proc(t: ^Tokenizer) -> bool {
    return is_number(t) && t.buf[t.offset] < '8'
}

is_valid_word_component :: proc(t: ^Tokenizer) -> bool {
    return is_alpha(t) || is_number(t) || is_char(t, '_')
}

is_whitespace :: proc(t: ^Tokenizer) -> bool {
    b := t.buf[t.offset]
    return b == ' ' || b == '\t'
}

// The below procedures are common ways of writing in various
// languages, so we made a common parsing procedure for them. If a
// language needs a different way of parsing them, I.e. JavaScript
// `==` and `===`, it should be handled by its tokenizer.
tokenizer_parse_asterisk :: proc(t: ^Tokenizer, token: ^Basic_Token) {
    token.kind = .Operation
    token.variant = .Asterisk
    t.offset += 1
    if is_eof(t) do return

    if is_char(t, '=') {
        token.variant = .Asterisk_Equal
        t.offset += 1
    }
}

tokenizer_parse_bang :: proc(t: ^Tokenizer, token: ^Basic_Token) {
    token.kind = .Operation
    token.variant = .Bang
    t.offset += 1
    if is_eof(t) do return

    if is_char(t, '=') {
        token.variant = .Bang_Equal
        t.offset += 1
    }
}

tokenizer_parse_equal :: proc(t: ^Tokenizer, token: ^Basic_Token) {
    token.kind = .Operation
    token.variant = .Equal
    t.offset += 1
    if is_eof(t) do return

    if is_char(t, '=') {
        token.variant = .Equal_Equal
        t.offset += 1
    }
}

tokenizer_parse_greater :: proc(t: ^Tokenizer, token: ^Basic_Token) {
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

tokenizer_parse_less :: proc(t: ^Tokenizer, token: ^Basic_Token) {
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

tokenizer_parse_minus :: proc(t: ^Tokenizer, token: ^Basic_Token) {
    token.kind = .Operation
    token.variant = .Minus
    t.offset += 1
    if is_eof(t) do return

    switch {
    case is_char(t, '='):
        token.variant = .Minus_Equal
        t.offset += 1
    case is_char(t, '>'):
        token.variant = .Minus_Greater
        t.offset += 1
    }
}

tokenizer_parse_pipe :: proc(t: ^Tokenizer, token: ^Basic_Token) {
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

tokenizer_parse_plus :: proc(t: ^Tokenizer, token: ^Basic_Token) {
    token.kind = .Operation
    token.variant = .Plus
    t.offset += 1
    if is_eof(t) do return

    if is_char(t, '=') {
        token.variant = .Plus_Equal
        t.offset += 1
    }
}

tokenizer_parse_slash :: proc(t: ^Tokenizer, token: ^Basic_Token) {
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

tokenizer_parse_tab :: proc(t: ^Tokenizer, token: ^Basic_Token) {
    token.kind = .Punctuation
    token.variant = .Tab
    t.offset += 1
    for !is_eof(t) && is_char(t, '\t') do t.offset += 1
}

tokenizer_parse_tilde :: proc(t: ^Tokenizer, token: ^Basic_Token) {
    token.kind = .Operation
    token.variant = .Tilde
    t.offset += 1
    if is_eof(t) do return

    if is_char(t, '=') {
        token.variant = .Tilde_Equal
        t.offset += 1
    }
}
