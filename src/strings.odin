package main

import "core:fmt"
import "core:unicode/utf8"
import "core:strings"

create_string_builder :: proc() -> strings.Builder {
    return strings.builder_make(context.temp_allocator)
}

// TODO: Fix this as it's not giving the correct value when there are multiple spaces
find_backward_word :: proc(line: string, point: int) -> int {
    delimiters := get_word_delimiters()

    for x := point - 1; x > 0; x -= 1 {
        if strings.contains_rune(delimiters, rune(line[x - 1])) {
            return x
        }
    }

    return 0
}

find_forward_word :: proc(line: string, point: int) -> int {
    delimiters := get_word_delimiters()
    part_of_the_string := strings.trim_left_space(line[point:])
    diff_point := len(line) - len(part_of_the_string)

    for x := diff_point + 1; x < len(line); x += 1 {
        test_string := line[x:x + 1]

        if strings.contains_any(test_string, delimiters) {
            return x
        }
    }

    return len(line)
}

get_string_indentation :: proc(s: string) -> int {
    for char, index in s { if char != ' ' && char != '\t' { return index } }
    return 0
}

get_word_delimiters :: proc() -> string {
    return " _-.\\/"
}
