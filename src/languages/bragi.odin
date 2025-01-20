package languages

import "core:strings"
import "core:unicode/utf8"

bragi_lexer :: proc(lexer: ^Lexer) {
    builtins := [?]string{
        "background", "cursor", "builtin", "comment", "constant",
        "default", "highlight", "keyword", "string",
    }

    switch {
    case lexer.current_rune == '#':
        lexer.state  = .Comment
        lexer.length = lexer.end_of_line

    case lexer.current_rune == '[':
        lexer.state  = .Default
        closing := strings.last_index(lexer.line, "]") + 1 - lexer.cursor
        lexer.length = closing > 0 ? closing : lexer.end_of_line

    case is_ascii(lexer.current_rune):
        if length, found := match_words(lexer.line, lexer.cursor, builtins[:]); found {
            lexer.length = length
            lexer.state  = .Builtin
        }

    case :
        lexer.state = .Default
    }
}
