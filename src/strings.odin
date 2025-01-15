package main

import "core:strings"

create_string_builder :: proc() -> strings.Builder {
    return strings.builder_make(context.temp_allocator)
}

find_backward_word :: proc(line: string, point: int) -> int {
    delimiters := get_word_delimiters()
    part_of_line_to_find_word := line[:point]
    return max(strings.last_index_any(part_of_line_to_find_word, delimiters), 0)
}

find_forward_word :: proc(line: string, point: int) -> int {
    delimiters := get_word_delimiters()
    part_of_line_to_find_word := line[point:]
    result := max(strings.index_any(part_of_line_to_find_word, delimiters) + 1, 0)
    return result > 0 ? result : len(line)
}

get_line_indentation :: proc(s: string) -> int {
    for char, index in s { if char != ' ' && char != '\t' { return index } }
    return 0
}

get_word_delimiters :: proc() -> string {
    return " _-."
}
