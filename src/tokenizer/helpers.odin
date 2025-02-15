#+private
package tokenizer

import "core:strings"

Test_Proc :: #type proc() -> bool

advance :: #force_inline proc() {
    T.offset += 1
}

is_eof :: #force_inline proc() -> bool {
    return T.offset >= len(S) - 1
}

is_whitespace :: #force_inline proc() -> bool {
    c := get_char()
    return c == ' ' || c == '\t' || c == '\n'
}

is_number :: #force_inline proc() -> bool {
    c := get_char()
    return c >= '0' && c <= '9'
}

is_char_in :: #force_inline proc(match: []byte) -> bool {
    for b in match {
        if get_char() == b {
            return true
        }
    }

    return false
}

previous_char :: #force_inline proc() -> byte {
    return S[T.offset - 1]
}

get_char :: #force_inline proc() -> byte {
    return S[T.offset]
}

peek_next_char :: #force_inline proc() -> byte {
    return S[T.offset + 1]
}

save_tokens :: #force_inline proc(k: Token_Kind, start, end: int) {
    for i in start..<end {
        R[i] = k
    }
}

scan_through_until_proc_false :: #force_inline proc(t: Test_Proc) -> (skipped: int) {
    for !is_eof() && t() {
        skipped += 1
        advance()
    }
    return
}

scan_through_until_word :: #force_inline proc(match: string) -> (skipped: int) {
    word := ""
    found := false
    start := T.offset

    for !found && !is_eof() {
        skipped += 1
        advance()

        if is_whitespace() {
            end := T.offset
            word = S[start:end]

            if word == match {
                return
            } else {
                start = end + 1
                word = ""
                advance()
            }
        }
    }

    return
}

scan_through_until_after_char :: #force_inline proc(match: byte) -> (skipped: int) {
    skipped = 2
    advance()
    for !is_eof() && get_char() != match {
        skipped += 1
        advance()
    }
    advance()
    return
}

scan_through_until_end_of_line :: #force_inline proc() -> (skipped: int) {
    for !is_eof() && get_char() != '\n' {
        skipped += 1
        advance()
    }
    return
}

scan_through_until_delimiter :: #force_inline proc(delimiter: string) -> (skipped: int) {
    for !is_eof() && !strings.contains_rune(delimiter, rune(get_char())) {
        skipped += 1
        advance()
    }
    return
}

scan_through_until_whitespace :: #force_inline proc() -> (skipped: int) {
    for !is_eof() && !is_whitespace() {
        skipped += 1
        advance()
    }
    return
}

skip_all_whitespaces :: #force_inline proc() {
    for c := get_char(); !is_eof() && is_whitespace(); {
        R[T.offset] = .generic
        advance()
    }
}
