package languages

import "core:strings"
import "core:unicode/utf8"

odin_lexer :: proc(lexer: ^Lexer) {
    keywords := []string{
        "asm", "auto_cast", "bit_set", "break", "case", "cast",
        "context", "continue", "defer", "delete", "distinct", "do", "dynamic",
        "else", "enum", "fallthrough", "for", "foreign", "if",
        "import", "in", "map", "not_in", "or_else", "or_return",
        "package", "proc", "return", "struct", "switch", "transmute",
        "typeid", "union", "using", "when", "where", "#load",
    }
    builtin := []string{

    }

    switch {
    case lexer.current_rune == '/':
        if utf8.rune_at(lexer.line, lexer.cursor + 1) == '/' {
            lexer.length = rest_of_line(lexer)
            lexer.state = .Comment
        }
    case lexer.current_rune == '"':
        lexer.state = .String
        closing := strings.last_index(lexer.line, "\"") + 1 - lexer.cursor
        lexer.length = closing > 0 ? closing : lexer.end_of_line
    case is_ascii(lexer.current_rune) || lexer.current_rune == '#':
        length: int
        found: bool

        if length, found = match_words(lexer.line, lexer.cursor, keywords[:]); found {
            lexer.length = length
            lexer.state  = .Keyword
        } else {
            lexer.state = .Default
            lexer.length = length
        }
    case :
        lexer.state = .Default
    }
}
