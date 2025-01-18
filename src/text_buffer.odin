package main

import "base:runtime"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

String_Cache_Type :: enum {
    None,
    Range,
    Full,
}

Text_Buffer :: struct {
    allocator  : runtime.Allocator,
    cursor     : int,
    data       : []u8,
    filepath   : string,
    gap_start  : int,
    gap_end    : int,
    modified   : bool,
    name       : string,
    strbuffer  : strings.Builder,
    str_cache  : String_Cache_Type,
    cache_size : int,
}

make_text_buffer :: proc(name: string, bytes_count: int, allocator := context.allocator) -> ^Text_Buffer {
    append(&bragi.buffers, Text_Buffer{
        allocator = allocator,
        data      = make([]u8, bytes_count, allocator),
        gap_end   = bytes_count,
        name      = name,
        strbuffer = strings.builder_make(),
    })
    text_buffer := &bragi.buffers[len(bragi.buffers) - 1]
    return text_buffer
}

make_text_buffer_from_file :: proc(filepath: string, allocator := context.allocator) -> ^Text_Buffer {
    log.debugf("Opening file {0}", filepath)
    data, success := os.read_entire_file_from_filename(filepath)
    parsed_data := buffer_clean_up_carriage_returns(data)
    text_buffer := make_text_buffer(filepath, len(parsed_data))
    insert_whole_file(text_buffer, parsed_data)
    text_buffer.filepath = filepath
    text_buffer.cursor = 0
    text_buffer.modified = len(data) != len(parsed_data)
    delete(data)
    return text_buffer
}

make_temp_strbuffer :: proc() -> strings.Builder {
    return strings.builder_make(context.temp_allocator)
}

delete_at :: proc(buffer: ^Text_Buffer, cursor: int, count: int) {
    buffer_delete(buffer, cursor, count)
    if count < 0 {
        buffer.cursor = max(0, buffer.cursor + count)
    }
}

insert_char_at :: proc(buffer: ^Text_Buffer, cursor: int, char: u8) {
    buffer_insert_char(buffer, cursor, char)
    buffer.cursor += 1
}

insert_char_at_point :: proc(buffer: ^Text_Buffer, char: u8) {
    insert_char_at(buffer, buffer.cursor, char)
}

insert_at :: proc(buffer: ^Text_Buffer, cursor: int, str: string) {
    buffer_insert(buffer, cursor, str)
    buffer.cursor += len(str)
}

insert_at_point :: proc(buffer: ^Text_Buffer, str: string) {
    insert_at(buffer, buffer.cursor, str)
}

insert_whole_file :: proc(buffer: ^Text_Buffer, data: []u8) {
    buffer_insert(buffer, 0, data)
    buffer.cursor = 0
    buffer.modified = false
}

length_of_buffer :: proc(buffer: ^Text_Buffer) -> int {
    gap := buffer.gap_end - buffer.gap_start
    return len(buffer.data) - gap
}

rune_at :: proc(buffer: ^Text_Buffer, cursor: int) -> rune {
    cursor := clamp(cursor, 0, length_of_buffer(buffer) - 1)
    left, right := buffer_get_strings(buffer)

    if cursor < len(left) {
        return rune(left[cursor])
    } else {
        return rune(right[cursor - len(left)])
    }
}

rune_at_point :: proc(buffer: ^Text_Buffer) -> rune {
    return rune_at(buffer, buffer.cursor)
}

line_start :: proc(buffer: ^Text_Buffer, cursor: int) -> int {
    str := entire_buffer_to_string(buffer)
    cursor := clamp(cursor, 0, length_of_buffer(buffer) - 1)

    for x := cursor - 1; x > 0; x -= 1 {
        if str[x] == '\n' {
            return x + 1
        }
    }

    return 0
}

line_end :: proc(buffer: ^Text_Buffer, cursor: int) -> int {
    cursor := clamp(cursor, 0, length_of_buffer(buffer) - 1)
    str := entire_buffer_to_string(buffer)

    for x := cursor; x < len(str); x += 1 {
        if str[x] == '\n' {
            return x
        }
    }

    return cursor
}

count_backward_words_offset :: proc(buffer: ^Text_Buffer, delimiters: string, cursor, count: int) -> int {
    found, offset: int
    starting_cursor := cursor
    str := entire_buffer_to_string(buffer)
    word_started := false

    for offset = starting_cursor; offset > 0; offset -= 1 {
        r := rune(str[offset])

        if !word_started {
            if !strings.contains_rune(delimiters, r) {
                word_started = true
            }
        } else {
            if strings.contains_rune(delimiters, r) {
                // NOTE: adjustment for better feeling when trying to find
                // or delete a previous word, since we don't need to get
                // stuck on the end of a line
                if r == '\n' { offset -= 1 }
                word_started = false
                found += 1
            }
        }

        if found == count {
            break
        }
    }

    return max(0, starting_cursor - offset)
}

count_forward_words_offset :: proc(buffer: ^Text_Buffer, delimiters: string, cursor, count: int) -> int {
    found, offset: int
    starting_cursor := cursor
    str := entire_buffer_to_string(buffer)
    word_started := false

    for offset = starting_cursor; offset < length_of_buffer(buffer) - 1; offset += 1 {
        r := rune(str[offset])

        if !word_started {
            if !strings.contains_rune(delimiters, r) {
                word_started = true
            }
        } else {
            if strings.contains_rune(delimiters, r) {
                word_started = false
                found += 1
            }
        }

        if found == count {
            break
        }
    }

    return max(0, offset - starting_cursor)
}

move_cursor_to :: proc(buffer: ^Text_Buffer, from, to: int, break_on_newline: bool) {
    str := entire_buffer_to_string(buffer)

    for x := from; x < len(str); x += 1 {
        buffer.cursor = x

        if x == to || (break_on_newline && str[x] == '\n') {
            break
        }
    }
}

save_buffer :: proc(buffer: ^Text_Buffer) {
    if buffer.modified {
        log.debugf("Saving {0}", buffer.name)
        str := entire_buffer_to_string(buffer)
        err := os.write_entire_file_or_err(buffer.filepath, transmute([]u8)str)

        if err != nil {
            log.errorf("Error saving buffer {0}\nError: {1}", buffer.name, err)
        }
    } else {
        log.debugf("Nothing to save in {0}", buffer.name)
    }
}

save_some_buffers :: proc() {
    log.debug("Saving some buffers")
    // TODO: Implement
}

flush_buffer_to_custom_string :: proc(buffer: ^Text_Buffer, strbuffer: ^strings.Builder, start, end: int) -> string {
    buffer_flush(buffer, strbuffer, start, end)
    return strings.to_string(strbuffer^)
}

range_buffer_to_string :: proc(buffer: ^Text_Buffer, start, end: int) -> string {
    if buffer.str_cache == .Range && buffer.cache_size == start + end {
        return strings.to_string(buffer.strbuffer)
    }

    clear(&buffer.strbuffer.buf)
    buffer_flush(buffer, &buffer.strbuffer, start, end)
    buffer.str_cache = .Range
    buffer.cache_size = start + end
    return strings.to_string(buffer.strbuffer)
}

entire_buffer_to_string :: proc(buffer: ^Text_Buffer) -> string {
    if buffer.str_cache == .Full {
        return strings.to_string(buffer.strbuffer)
    }

    log.debugf("- Generating new string for buffer {0}", buffer.name)
    clear(&buffer.strbuffer.buf)
    buffer_flush_everything(buffer)
    buffer.str_cache = .Full
    return strings.to_string(buffer.strbuffer)
}

@(private="file")
buffer_flush :: proc(buffer: ^Text_Buffer, strbuffer: ^strings.Builder, start, end: int) {
    left, right := buffer_get_strings(buffer)
    assert(start >= 0, "invalid cursor start position")
    assert(end <= length_of_buffer(buffer), "invalid cursor end position")

    left_len := len(left)

    if end <= left_len {
        strings.write_string(strbuffer, left[start:end])
    } else if start >= left_len {
        strings.write_string(strbuffer, right[start - left_len:end - left_len])
    } else {
        strings.write_string(strbuffer, left[start:])
        strings.write_string(strbuffer, right[:end - left_len])
    }
}

@(private="file")
buffer_flush_everything :: proc(buffer: ^Text_Buffer) {
    buffer_flush(buffer, &buffer.strbuffer, 0, length_of_buffer(buffer))
}

@(private="file")
buffer_get_strings :: proc(buffer: ^Text_Buffer) -> (string, string) {
    left := string(buffer.data[:buffer.gap_start])
    right := string(buffer.data[buffer.gap_end:])
    return left, right
}

@(private="file")
buffer_move_gap :: proc(buffer: ^Text_Buffer, cursor: int) {
    cursor := clamp(cursor, 0, length_of_buffer(buffer))
    buffer.str_cache = .None
    buffer.modified = true

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

@(private="file")
buffer_clean_up_carriage_returns :: proc(data: []u8) -> []u8 {
    parsed_data := slice.clone_to_dynamic(data, context.temp_allocator)
    for char, index in parsed_data {
        if char == '\r' {
            ordered_remove(&parsed_data, index)
        }
    }
    return parsed_data[:]
}
