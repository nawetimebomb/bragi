package tokenizer

import "core:time"

Token_Type :: enum {
    Builtin,
    Constant,
    Comment,
    Keyword,
    String,
    Word,
}

Token_Location :: struct {
    column: int,
    line: int,
}

Token :: struct {
    location: Token_Location,
    text: string,
    type: Token_Type,
}

Tokenizer :: struct {
    buf: string,
    generation_time: time.Tick,
    tokens: [dynamic]Token,
}
