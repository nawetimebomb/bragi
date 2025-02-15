package tokenizer

import "core:slice"

@private
R: ^[dynamic]Token_Kind

@private
S: ^string

@private
T: Tokenizer

@private
Tokenizer :: struct {
    offset: int,
}

@private
tokenizer_init :: proc(s: ^string, start_offset: int, tokens: ^[dynamic]Token_Kind) {
    T.offset = start_offset
    S = s
    R = tokens
}

@private
tokenizer_finish :: proc() {
    S = nil
    T = Tokenizer{}
    R = nil
}

@private
tokenizer_complete :: proc() -> bool {
    advance()
    return is_eof()
}

Token_Kind :: enum u8 {
    generic = 0,
    builtin,
    comment,
    constant,
    keyword,
    preprocessor,
    string,
    type,
}
