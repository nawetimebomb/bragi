package languages

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

bragi_lexer :: proc(rs: ^Render_State) {
    builtin_words := [?]string{
        "background", "cursor", "builtin", "comment", "constant",
        "default", "highlight", "keyword", "string",
    }

    switch {
    case strings.is_space(rs.current_rune):
        rs.state = .Default
        return
    case rs.current_rune == '#':
        rs.state  = .Comment
        rs.length = rs.end_of_line
        return

    case rs.current_rune == '[':
        rs.state  = .Highlight
        closing := strings.last_index(rs.line, "]") + 1 - rs.cursor
        rs.length = closing > 0 ? closing : rs.end_of_line
        return
    case is_ascii(rs.current_rune):
        if length, found := match_words(rs.line, rs.cursor, builtin_words[:]); found {
            rs.length = length
            rs.state = .Builtin
        }
    }
}
