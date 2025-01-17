package main

import "core:fmt"

import "base:runtime"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"

Text_Buffer :: struct {
    allocator : runtime.Allocator,
    cursor    : int,
    data      : []u8,
    filepath  : string,
    gap_start : int,
    gap_end   : int,
    lines     : [dynamic]int,
    name      : string,
    strbuffer : strings.Builder,
}

make_text_buffer :: proc(bytes_count: int, allocator := context.allocator) -> Text_Buffer {
    return Text_Buffer{
        allocator = allocator,
        data      = make([]u8, bytes_count, allocator),
        gap_end   = bytes_count,
        strbuffer = strings.builder_make(context.temp_allocator),
    }
}

delete_at :: proc(buffer: ^Text_Buffer, cursor: int, count: int) {
    buffer_delete(buffer, cursor, count)
    if count < 0 {
        buffer.cursor = max(0, buffer.cursor + count)
    }
    buffer_calculate_lines(buffer)
}

insert_new_file :: proc(buffer: ^Text_Buffer, data: []u8) {
    buffer_insert(buffer, 0, data)
    buffer.cursor = 0
    buffer_calculate_lines(buffer)
}

insert_at :: proc(buffer: ^Text_Buffer, cursor: int, str: string) {
    buffer_insert(buffer, cursor, str)
    buffer.cursor += len(str)
    buffer_calculate_lines(buffer)
}

insert_at_point :: proc(buffer: ^Text_Buffer, str: string) {
    insert_at(buffer, buffer.cursor, str)
}

length_of_buffer :: proc(buffer: ^Text_Buffer) -> int {
    gap := buffer.gap_end - buffer.gap_start
    return len(buffer.data) - gap
}

newline :: proc(buffer: ^Text_Buffer) {
    buffer_insert_char(buffer, buffer.cursor, '\n')
    buffer.cursor += 1
}

rune_at :: proc(buffer: ^Text_Buffer) -> rune {
    cursor := clamp(buffer.cursor, 0, length_of_buffer(buffer) - 1)
    left, right := buffer_get_strings(buffer)

    if cursor < len(left) {
        return rune(left[cursor])
    } else {
        return rune(right[cursor - len(left)])
    }
}

flush_range :: proc(buffer: ^Text_Buffer, start, end: int) {
    left, right := buffer_get_strings(buffer)
    assert(start >= 0, "invalid cursor start position")
    assert(end <= length_of_buffer(buffer), "invalid cursor end position")

    left_len := len(left)

    if end <= left_len {
        strings.write_string(&buffer.strbuffer, left[start:end])
    } else if start >= left_len {
        strings.write_string(&buffer.strbuffer, right[start - left_len:end - left_len])
    } else {
        strings.write_string(&buffer.strbuffer, left[start:])
        strings.write_string(&buffer.strbuffer, right[:end - left_len])
    }
}

flush_entire_buffer :: proc(buffer: ^Text_Buffer) {
    flush_range(buffer, 0, length_of_buffer(buffer))
}

entire_buffer_to_string :: proc(buffer: ^Text_Buffer) -> string {
    flush_entire_buffer(buffer)
    str := strings.to_string(buffer.strbuffer)
    clear(&buffer.strbuffer.buf)
    return str
}

@(private="file")
buffer_get_strings :: proc(buffer: ^Text_Buffer) -> (string, string) {
    left := string(buffer.data[:buffer.gap_start])
    right := string(buffer.data[buffer.gap_end:])
    return left, right
}

@(private="file")
buffer_move_gap :: proc(buffer: ^Text_Buffer, cursor: int) {
    gap_len := buffer.gap_end - buffer.gap_start
    cursor := clamp(cursor, 0, len(buffer.data) - gap_len)

    if cursor == buffer.gap_start {
        return
    }

    if buffer.gap_start < cursor {
        delta := cursor - buffer.gap_start
        mem.copy(&buffer.data[buffer.gap_start], &buffer.data[buffer.gap_end], delta)
        buffer.gap_start += delta
        buffer.gap_end += delta
    } else {
        delta := buffer.gap_start - cursor
        mem.copy(&buffer.data[buffer.gap_end - delta],
                 &buffer.data[buffer.gap_start - delta], delta)
        buffer.gap_start -= delta
        buffer.gap_end -= delta
    }
}

@(private="file")
conditionally_grow_buffer :: proc(buffer: ^Text_Buffer, bytes_count: int) {
    gap_len := buffer.gap_end - buffer.gap_start

    if gap_len < bytes_count {
        required_new_data_array_size := bytes_count + len(buffer.data) - gap_len
        new_data_len := max(2 * len(buffer.data), required_new_data_array_size)

        buffer_move_gap(buffer, len(buffer.data) - gap_len)
        new_data_array := make([]u8, new_data_len, buffer.allocator)
        copy_slice(new_data_array, buffer.data[:buffer.gap_end])
        delete(buffer.data)
        buffer.data = new_data_array
        buffer.gap_end = len(new_data_array)
    }
}

@(private="file")
buffer_calculate_lines :: proc(buffer: ^Text_Buffer) {
    // TODO: It shouldn't clear all lines, but the ones affected, after the current
    // cursor position
    clear(&buffer.lines)
    left, right := buffer_get_strings(buffer)
    append(&buffer.lines, 0)

    for i := 0 ; i < len(left); i += 1 {
        if left[i] == '\n' {
            append(&buffer.lines, i + 1)
        }
    }

    for i := 0 ; i < len(right); i += 1 {
        if right[i] == '\n' {
            append(&buffer.lines, len(left) + i + 1)
        }
    }
}

@(private="file")
buffer_line_len :: proc(buffer: ^Text_Buffer, line: int) -> int {
    assert(line >= 0 && line <= len(buffer.lines), "Array overflow")

    if line >= len(buffer.lines) - 1 {
        buf_len := length_of_buffer(buffer)
        return buf_len - buffer.lines[len(buffer.lines) - 1]
    } else {
        starts_at := buffer.lines[line]
        next_at := buffer.lines[line + 1]
        return next_at - starts_at
    }
}

@(private="file")
buffer_delete :: proc(buffer: ^Text_Buffer, cursor: int, count: int) {
    chars_to_delete := abs(count)
    canon_cursor := cursor

    if count < 0 {
        canon_cursor = max(0, canon_cursor - chars_to_delete)
    }

    buffer_move_gap(buffer, canon_cursor)
    buffer.gap_end = min(buffer.gap_end + chars_to_delete, len(buffer.data))
}

@(private="file")
buffer_insert :: proc{
    buffer_insert_char,
    buffer_insert_rune,
    buffer_insert_array,
    buffer_insert_string,
}

@(private="file")
buffer_insert_char :: proc(buffer: ^Text_Buffer, cursor: int, char: u8) {
    conditionally_grow_buffer(buffer, 1)
    buffer_move_gap(buffer, cursor)
    buffer.data[buffer.gap_start] = char
    buffer.gap_start += 1
}

@(private="file")
buffer_insert_rune :: proc(buffer: ^Text_Buffer, cursor: int, r: rune) {
    bytes, _ := utf8.encode_rune(r)
    buffer_insert_array(buffer, cursor, bytes[:])
}

@(private="file")
buffer_insert_array :: proc(buffer: ^Text_Buffer, cursor: int, array: []u8) {
    conditionally_grow_buffer(buffer, len(array))
    buffer_move_gap(buffer, cursor)
    copy_slice(buffer.data[buffer.gap_start:], array)
    buffer.gap_start += len(array)
}

@(private="file")
buffer_insert_string :: proc(buffer: ^Text_Buffer, cursor: int, str: string) {
    buffer_insert_array(buffer, cursor, transmute([]u8)str)
}
