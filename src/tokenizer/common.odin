package tokenizer

import "core:slice"

@private
R: []Token_Kind

@private
S: ^string

@private
T: Tokenizer

@private
Tokenizer :: struct {
    column: int,
    line:   int,
    offset: int,
}

@private
tokenizer_init :: proc(s: ^string) {
    T.column = -1
    T.offset = -1
    S = s
    R = make([]Token_Kind, len(s))
}

tokenizer_finish :: proc() -> []Token_Kind {
    result := slice.clone(R[:])
    S = nil
    T = Tokenizer{}
    delete(R)
    return result
}

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
    string,
    type,
}
