package main

/*
 * Buffers should be certainly smarter... Maybe the way to do it is not
 * to use a gap buffer, but the string buffer instead.
 * https://github.com/odin-lang/Odin/blob/master/core/text/edit/text_edit.odin#L348
 */

import "base:runtime"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf8"


String_Cache_Type :: enum {
    None,
    Range,
    Full,
}

Gap_Buffer :: struct {
    allocator : runtime.Allocator,
    buf       : []u8,
    gap_end   : int,
    gap_start : int,
}

Text_Buffer_State :: struct {
    cursor:    int,
    data:      []u8,
    gap_end:   int,
    gap_start: int,
    dirty:     bool,
}

Text_Buffer :: struct {
    data_buffer:    Gap_Buffer,
    str_buffer:     strings.Builder,
    str_cache:      String_Cache_Type,
    cache_size:     int,
    cursor:         int,

    undo:           [dynamic]Text_Buffer_State,
    redo:           [dynamic]Text_Buffer_State,
    last_edit_time: time.Tick,
    current_time:   time.Tick,

    filepath:       string,
    major_mode:     Major_Mode,
    name:           string,
    readonly:       bool,
    dirty:          bool,
}

make_text_buffer :: proc(name: string, bytes_count: int, allocator := context.allocator) -> ^Text_Buffer {
    append(&bragi.buffers, Text_Buffer{
        data_buffer = {
            allocator = allocator,
            buf       = make([]u8, bytes_count, allocator),
            gap_end   = bytes_count,
        },

        undo       = make([dynamic]Text_Buffer_State, 0, 20),
        redo       = make([dynamic]Text_Buffer_State, 0, 10),

        major_mode = .Fundamental,
        name       = strings.clone(name),
        str_buffer = strings.builder_make(),
    })
    return &bragi.buffers[len(bragi.buffers) - 1]
}

make_text_buffer_from_file :: proc(filepath: string, allocator := context.allocator) -> ^Text_Buffer {
    norm_filepath, _ := strings.replace_all(filepath, "\\", "/", context.temp_allocator)
    split_filepath := strings.split(norm_filepath, "/", context.temp_allocator)
    name := split_filepath[len(split_filepath) - 1]
    split_filename := strings.split(name, ".", context.temp_allocator)
    extension := split_filename[len(split_filename) - 1]
    data, success := os.read_entire_file_from_filename(filepath)

    log.debugf("Opening file {0} in buffer {1}", filepath, name)

    text_buffer := make_text_buffer(name, len(data))

    insert_whole_file(text_buffer, data)
    text_buffer.filepath = filepath
    text_buffer.cursor = 0
    text_buffer.major_mode = find_major_mode(extension)

    log.debugf("File {0} complete", filepath)

    delete(data)
    return text_buffer
}

make_temp_str_buffer :: proc() -> strings.Builder {
    return strings.builder_make(context.temp_allocator)
}

destroy_text_buffer :: proc(buffer: ^Text_Buffer) {
    text_buffer_undo_clear(&buffer.undo)
    text_buffer_undo_clear(&buffer.redo)
    delete(buffer.data_buffer.buf)
    delete(buffer.name)
    delete(buffer.redo)
    delete(buffer.str_buffer.buf)
    delete(buffer.undo)
}

delete_at :: proc(buffer: ^Text_Buffer, cursor: int, count: int) {
    text_buffer_undo_check(buffer)
    buffer_delete(&buffer.data_buffer, cursor, count)
    if count < 0 {
        buffer.cursor = max(0, buffer.cursor + count)
    }
    simple_text_buffer_update(buffer)
}

insert_char_to_text_buffer :: proc(buffer: ^Text_Buffer, cursor: int, char: u8) {
    text_buffer_undo_check(buffer)
    buffer_insert(&buffer.data_buffer, cursor, char)
    buffer.cursor += 1
    simple_text_buffer_update(buffer)
}

insert_str_to_text_buffer :: proc(buffer: ^Text_Buffer, cursor: int, str: string) {
    text_buffer_undo_check(buffer)
    buffer_insert(&buffer.data_buffer, cursor, str)
    buffer.cursor += len(str)
    simple_text_buffer_update(buffer)
}

insert_at :: proc{
    insert_char_to_text_buffer,
    insert_str_to_text_buffer,
}

insert_whole_file :: proc(buffer: ^Text_Buffer, data: []u8) {
    buffer_insert(&buffer.data_buffer, 0, data)
    buffer.cursor = 0
    buffer.dirty  = false
}

length_of_buffer :: proc(buffer: ^Text_Buffer) -> int {
    return buffer_len(&buffer.data_buffer)
}

line_boundaries :: proc(buffer: ^Text_Buffer, cursor: int) -> (begin, end: int) {
    begin = cursor; end = cursor
    str := entire_buffer_to_string(buffer)

    for {
        begin_found, end_found: bool

        if begin > 0 && str[begin - 1] != '\n' {
            begin -= 1
        } else {
            begin_found = true
        }

        if end < len(str) - 1 && str[end] != '\n' {
            end += 1
        } else {
            end_found = true
        }

        if begin_found && end_found {
            return
        }
    }
}

@(deprecated="Use line_boundaries")
line_start :: proc(buffer: ^Text_Buffer, cursor: int) -> int {
    sol, _ := line_boundaries(buffer, cursor)
    return sol
}

@(deprecated="Use line_boundaries")
line_end :: proc(buffer: ^Text_Buffer, cursor: int) -> int {
    _, eol := line_boundaries(buffer, cursor)
    return eol
}

line_len :: proc(buffer: ^Text_Buffer, cursor: int) -> int {
    sol, eol := line_boundaries(buffer, cursor)
    return eol - sol
}

word_boundaries :: proc(buffer: ^Text_Buffer, cursor: int) -> (begin, end: int) {
    begin = cursor; end = cursor
    str := entire_buffer_to_string(buffer)
    delimiters := settings_get_word_delimiters(buffer.major_mode)

    for {
        begin_found, end_found: bool
        begin_rune := rune(str[begin - 1])
        end_rune   := rune(str[end])

        if begin > 0 && !strings.contains_rune(delimiters, begin_rune) {
            begin -= 1
        } else {
            begin_found = true
        }

        if end < len(str) - 1 && !strings.contains_rune(delimiters, end_rune) {
            end += 1
        } else {
            end_found = true
        }

        if begin_found && end_found {
            return
        }
    }
}

count_backward_words_offset :: proc(buffer: ^Text_Buffer, cursor, count: int) -> int {
    found, offset: int
    starting_cursor := cursor
    str := entire_buffer_to_string(buffer)
    word_started := false
    delimiters := settings_get_word_delimiters(buffer.major_mode)

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

count_forward_words_offset :: proc(buffer: ^Text_Buffer, cursor, count: int) -> int {
    found, offset: int
    starting_cursor := cursor
    str := entire_buffer_to_string(buffer)
    word_started := false
    delimiters := settings_get_word_delimiters(buffer.major_mode)

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
    if buffer.dirty {
        log.debugf("Saving {0}", buffer.name)
        text_buffer_sanitize(buffer)
        str := entire_buffer_to_string(buffer)
        err := os.write_entire_file_or_err(buffer.filepath, transmute([]u8)str)

        if err != nil {
            log.errorf("Error saving buffer {0}\nError: {1}", buffer.name, err)
        } else {
            buffer.dirty = false
        }
    } else {
        log.debugf("Nothing to save in {0}", buffer.name)
    }
}

save_some_buffers :: proc() {
    log.debug("Saving some buffers")
    // TODO: Implement
}

search_buffer :: proc(buffer: ^Text_Buffer, query: string, results: ^[dynamic]int) {
    str := entire_buffer_to_string(buffer)
    og_str_len := len(str)

    for {
        index := strings.index(str, query)

        if index == -1 {
            break
        }

        append(results, og_str_len - len(str) + index)
        str = str[index + len(query):]
    }
}

update_text_buffer_time :: proc(buffer: ^Text_Buffer) {
    buffer.current_time = time.tick_now()
}

flush_buffer_to_custom_string :: proc(buffer: ^Text_Buffer, str_buffer: ^strings.Builder, start, end: int) -> string {
    buffer_flush(&buffer.data_buffer, str_buffer, start, end)
    return strings.to_string(str_buffer^)
}

range_buffer_to_string :: proc(buffer: ^Text_Buffer, start, end: int) -> string {
    if buffer.str_cache == .Range && buffer.cache_size == start + end {
        return strings.to_string(buffer.str_buffer)
    }

    strings.builder_reset(&buffer.str_buffer)
    buffer_flush(&buffer.data_buffer, &buffer.str_buffer, start, end)
    buffer.str_cache = .Range
    buffer.cache_size = start + end
    return strings.to_string(buffer.str_buffer)
}

entire_buffer_to_string :: proc(buffer: ^Text_Buffer) -> string {
    if buffer.str_cache == .Full {
        return strings.to_string(buffer.str_buffer)
    }

    strings.builder_reset(&buffer.str_buffer)
    buffer_flush_everything(&buffer.data_buffer, &buffer.str_buffer)
    buffer.str_cache = .Full
    return strings.to_string(buffer.str_buffer)
}

get_buffer_status :: proc(buffer: ^Text_Buffer) -> string {
    temp_buffer := make_temp_str_buffer()
    strings.write_string(&temp_buffer, buffer.dirty ? "*" : "-")
    return strings.to_string(temp_buffer)
}

undo_redo :: proc(buffer: ^Text_Buffer, undo, redo: ^[dynamic]Text_Buffer_State) {
    if len(undo) > 0 {
        text_buffer_state_push(buffer, redo)
        item := pop(undo)

        buffer.cursor                = item.cursor
        buffer.data_buffer.gap_end   = item.gap_end
        buffer.data_buffer.gap_start = item.gap_start
        buffer.dirty                 = item.dirty

        delete(buffer.data_buffer.buf)
        buffer.data_buffer.buf = slice.clone(item.data, buffer.data_buffer.allocator)
        delete(item.data)
        simple_text_buffer_update(buffer)
    }
}

canonicalize_mouse_to_buffer :: proc(buffer: ^Text_Buffer, x, y: int) {
    buffer_str := entire_buffer_to_string(buffer)
    local_x, local_y: int

    for r, index in buffer_str {
        if local_y == y {
            bol, eol := line_boundaries(buffer, index)
            length := eol - bol

            if length > x {
                buffer.cursor = bol + x
            } else {
                buffer.cursor = eol
            }

            return
        }

        local_x += 1

        if r == '\n' {
            local_x = 0
            local_y += 1
        }
    }
}

@(private="file")
text_buffer_undo_check :: proc(buffer: ^Text_Buffer) {
    text_buffer_undo_clear(&buffer.redo)
    if time.tick_diff(buffer.last_edit_time, buffer.current_time) > UNDO_TIMEOUT {
        log.debug("Pushing a new UNDO state")
        text_buffer_state_push(buffer, &buffer.undo)
    }
    buffer.last_edit_time = buffer.current_time
}

@(private="file")
text_buffer_state_push :: proc(buffer: ^Text_Buffer, undo: ^[dynamic]Text_Buffer_State) -> mem.Allocator_Error {
    item := Text_Buffer_State{
        cursor    = buffer.cursor,
        data      = slice.clone(buffer.data_buffer.buf, bragi.ctx.undo_allocator),
        gap_end   = buffer.data_buffer.gap_end,
        gap_start = buffer.data_buffer.gap_start,
        dirty     = buffer.dirty,
    }

    append(undo, item) or_return
    return nil
}

@(private="file")
text_buffer_undo_clear :: proc(undo: ^[dynamic]Text_Buffer_State) {
    for len(undo) > 0 {
        item := pop(undo)
        delete(item.data)
    }
    clear(undo)
}

@(private="file")
simple_text_buffer_update :: proc(buffer: ^Text_Buffer) {
    buffer.cache_size = 0
    buffer.str_cache  = .None
    buffer.dirty      = true
}

@(private="file")
text_buffer_sanitize :: proc(buffer: ^Text_Buffer) {
    og_cursor_pos := buffer.cursor
    EOF_LF_COUNT :: 2
    str := entire_buffer_to_string(buffer)
    last_char := len(str) - 1
    line_endings := 0
    buf_len := buffer_len(&buffer.data_buffer)

    for x := last_char; x > 0; x -= 1 {
        if str[x] != '\n' {
            break
        }

        line_endings += 1
    }

    if line_endings < EOF_LF_COUNT {
        for ; line_endings > 0; line_endings -= 1 {
            insert_at(buffer, buf_len, '\n')
        }
    } else {
        delete_at(buffer, buf_len, EOF_LF_COUNT - line_endings)
    }

    buffer.cursor = clamp(og_cursor_pos, 0, length_of_buffer(buffer) - 1)
}

@(private="file")
buffer_flush :: proc(buffer: ^Gap_Buffer, str_buffer: ^strings.Builder, start, end: int) {
    left, right := buffer_get_strings(buffer)
    assert(start >= 0, "invalid cursor start position")
    assert(end <= buffer_len(buffer), "invalid cursor end position")

    left_len := len(left)

    if end <= left_len {
        strings.write_string(str_buffer, left[start:end])
    } else if start >= left_len {
        strings.write_string(str_buffer, right[start - left_len:end - left_len])
    } else {
        strings.write_string(str_buffer, left[start:])
        strings.write_string(str_buffer, right[:end - left_len])
    }
}

@(private="file")
buffer_flush_everything :: proc(buffer: ^Gap_Buffer, str_buffer: ^strings.Builder) {
    buffer_flush(buffer, str_buffer, 0, buffer_len(buffer))
}

@(private="file")
buffer_get_strings :: proc(buffer: ^Gap_Buffer) -> (string, string) {
    left := string(buffer.buf[:buffer.gap_start])
    right := string(buffer.buf[buffer.gap_end:])
    return left, right
}

@(private="file")
buffer_len :: proc(buffer: ^Gap_Buffer) -> int {
    gap := buffer.gap_end - buffer.gap_start
    return len(buffer.buf) - gap
}

@(private="file")
buffer_move_gap :: proc(buffer: ^Gap_Buffer, cursor: int) {
    cursor := clamp(cursor, 0, buffer_len(buffer))

    if cursor == buffer.gap_start {
        return
    }

    if buffer.gap_start < cursor {
        delta := cursor - buffer.gap_start
        mem.copy(&buffer.buf[buffer.gap_start], &buffer.buf[buffer.gap_end], delta)
        buffer.gap_start += delta
        buffer.gap_end += delta
    } else {
        delta := buffer.gap_start - cursor
        mem.copy(&buffer.buf[buffer.gap_end - delta],
                 &buffer.buf[buffer.gap_start - delta], delta)
        buffer.gap_start -= delta
        buffer.gap_end -= delta
    }
}

@(private="file")
conditionally_grow_buffer :: proc(buffer: ^Gap_Buffer, bytes_count: int) {
    gap_len := buffer.gap_end - buffer.gap_start

    if gap_len < bytes_count {
        required_new_data_array_size := bytes_count + len(buffer.buf) - gap_len
        new_data_len := max(2 * len(buffer.buf), required_new_data_array_size)

        buffer_move_gap(buffer, len(buffer.buf) - gap_len)
        new_data_array := make([]u8, new_data_len, buffer.allocator)
        copy_slice(new_data_array, buffer.buf[:buffer.gap_end])
        delete(buffer.buf)
        buffer.buf = new_data_array
        buffer.gap_end = len(new_data_array)
    }
}

@(private="file")
buffer_delete :: proc(buffer: ^Gap_Buffer, cursor: int, count: int) {
    chars_to_delete := abs(count)
    canon_cursor := cursor

    if count < 0 {
        canon_cursor = max(0, canon_cursor - chars_to_delete)
    }

    buffer_move_gap(buffer, canon_cursor)
    buffer.gap_end = min(buffer.gap_end + chars_to_delete, len(buffer.buf))
}

@(private="file")
buffer_insert_char :: proc(buffer: ^Gap_Buffer, cursor: int, char: u8) {
    conditionally_grow_buffer(buffer, 1)
    buffer_move_gap(buffer, cursor)
    buffer.buf[buffer.gap_start] = char
    buffer.gap_start += 1
}

@(private="file")
buffer_insert_rune :: proc(buffer: ^Gap_Buffer, cursor: int, r: rune) {
    bytes, _ := utf8.encode_rune(r)
    buffer_insert_array(buffer, cursor, bytes[:])
}

@(private="file")
buffer_insert_array :: proc(buffer: ^Gap_Buffer, cursor: int, array: []u8) {
    conditionally_grow_buffer(buffer, len(array))
    buffer_move_gap(buffer, cursor)
    copy_slice(buffer.buf[buffer.gap_start:], array)
    buffer.gap_start += len(array)
}

@(private="file")
buffer_insert_string :: proc(buffer: ^Gap_Buffer, cursor: int, str: string) {
    buffer_insert_array(buffer, cursor, transmute([]u8)str)
}

@(private="file")
buffer_insert :: proc{
    buffer_insert_char,
    buffer_insert_rune,
    buffer_insert_array,
    buffer_insert_string,
}

@(private="file")
buffer_sanitize_file_data :: proc(data: []u8) -> []u8 {
    parsed_data := slice.clone_to_dynamic(data, context.temp_allocator)
    count_line_endings := 0

    for char, index in parsed_data {
        if char == '\r' {
            ordered_remove(&parsed_data, index)
        }
    }

    for x := len(parsed_data) - 1; x > 0; x -= 1 {
        if parsed_data[x] != '\n' {
            break
        }

        count_line_endings += 1
    }

    if count_line_endings < 2 {
        for ; count_line_endings > 0; count_line_endings -= 1 {
            append(&parsed_data, '\n')
        }
    } else {
        for count_line_endings > 2 {
            pop(&parsed_data)
            count_line_endings -= 1
        }
    }

    diff_between_buffers := len(data) - len(parsed_data)

    if diff_between_buffers > 0 {
        log.debugf("Cleaned up {0} characters", diff_between_buffers)
    }

    return parsed_data[:]
}
