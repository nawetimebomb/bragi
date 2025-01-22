package main

import "base:runtime"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

UNDO_DEFAULT_TIMEOUT :: 300 * time.Millisecond

EOL_Sequence :: enum { LF, CRLF, }

History_State :: struct {
    cursor:    int,
    data:      []u8,
    gap_end:   int,
    gap_start: int,
}

Buffer :: struct {
    allocator:      runtime.Allocator,

    cursor:         int,
    data:           []u8,
    dirty:          bool,
    was_dirty:      bool,
    gap_end:        int,
    gap_start:      int,

    enable_history: bool,
    redo:           [dynamic]History_State,
    undo:           [dynamic]History_State,
    history_limit:  int,
    current_time:   time.Tick,
    last_edit_time: time.Tick,
    undo_timeout:   time.Duration,

    builder:        ^strings.Builder,

    filepath:       string,
    major_mode:     Major_Mode,
    name:           string,
    readonly:       bool,
    modified:       bool,
    eol_sequence:   EOL_Sequence,
}

create_buffer :: proc(
    name: string,
    bytes: int,
    undo_timeout := UNDO_DEFAULT_TIMEOUT,
    allocator := context.allocator,
) -> ^Buffer {
    append(&bragi._buffers, Buffer{
        allocator    = allocator,
        data         = make([]u8, bytes, allocator),
        gap_end      = bytes,
        major_mode   = .Fundamental,
        name         = strings.clone(name),
        redo         = make([dynamic]History_State, 0, 5),
        undo         = make([dynamic]History_State, 0, 5),
        undo_timeout = undo_timeout,
    })

    result := &bragi._buffers[len(bragi._buffers) - 1]

    result.undo.allocator = allocator
    result.redo.allocator = allocator

    return result
}

create_buffer_from_file :: proc(
    filepath: string,
    undo_timeout := UNDO_DEFAULT_TIMEOUT,
    allocator := context.allocator,
) -> ^Buffer {
    posix_filepath, _ := strings.replace_all(filepath, "\\", "/", context.temp_allocator)
    splitted_filepath := strings.split(posix_filepath, "/", context.temp_allocator)
    name := splitted_filepath[len(splitted_filepath) - 1]
    splitted_name := strings.split(name, ".", context.temp_allocator)
    extension := splitted_name[len(splitted_name) - 1]
    data, success := os.read_entire_file(filepath, context.temp_allocator)

    if !success {
        log.errorf("Failed to open file {0}", filepath)
        return nil
    }

    result := create_buffer(name, len(data), undo_timeout, allocator)
    result.filepath = filepath
    result.major_mode = find_major_mode(extension)

    insert(result, 0, data)
    result.cursor = 0

    return result
}

begin_buffer :: proc(buffer: ^Buffer, builder: ^strings.Builder) {
    assert(builder != nil)
    assert(!buffer.dirty)
    buffer.builder = builder
    update_buffer_time(buffer)

    if buffer.was_dirty || len(builder.buf) == 0 {
        buffer.was_dirty = false
        rebuild_string_buffer(buffer)
    }
}

update_buffer_time :: proc(buffer: ^Buffer) {
    buffer.current_time = time.tick_now()
	if buffer.undo_timeout <= 0 {
		buffer.undo_timeout = UNDO_DEFAULT_TIMEOUT
	}
}

end_buffer :: proc(buffer: ^Buffer) {
    buffer.builder = nil

    if buffer.dirty {
        buffer.dirty = false
        buffer.was_dirty = true
    }
}

destroy_buffer :: proc(buffer: ^Buffer) {
    clear_history(&buffer.undo)
    clear_history(&buffer.redo)
    delete(buffer.data)
    delete(buffer.name)
    delete(buffer.redo)
    delete(buffer.undo)
    buffer.builder = nil
}

_get_buffer_status :: proc(buffer: ^Buffer) -> (status: string) {
    switch {
    case buffer.modified: status = "*"
    case buffer.readonly: status = "%"
    case                : status = " "
    }

    return
}

get_line_boundaries :: proc(buffer: ^Buffer, pos: int) -> (begin, end: int) {
    begin = pos; end = pos
    data := buffer.builder.buf

    for {
        bsearch := begin > 0 && data[begin - 1] != '\n'
        esearch := end < len(data) - 1 && data[end] != '\n'
        if bsearch { begin -= 1 }
        if esearch { end += 1 }
        if !bsearch && !esearch { return }
    }
}

get_line_length :: proc(buffer: ^Buffer, pos: int) -> int {
    bol, eol := get_line_boundaries(buffer, pos)
    return eol - bol
}

get_word_boundaries :: proc(buffer: ^Buffer, pos: int) -> (begin, end: int) {
    begin = pos; end = pos
    data := string(buffer.builder.buf[:])
    delimiters := settings_get_word_delimiters(buffer.major_mode)

    for {
        brune := utf8.rune_at(data, begin - 1)
        erune := utf8.rune_at(data, end)
        bsearch := begin > 0 && !strings.contains_rune(delimiters, brune)
        esearch := end < len(data) - 1 && !strings.contains_rune(delimiters, erune)
        if bsearch { begin -= 1 }
        if esearch { end += 1 }
        if !bsearch && !esearch { return }
    }
}

buffer_search :: proc(buffer: ^Buffer, query: string) -> []int {
    results := make([dynamic]int, 0, 10, context.temp_allocator)
    str := string(buffer.builder.buf[:])
    initial_length := len(str)

    for {
        index := strings.index(str, query)
        if index == -1 { break }
        append(&results, initial_length - len(str) + index)
        str = str[index + len(query):]
    }

    return slice.clone(results[:])
}

clear_history :: proc(history: ^[dynamic]History_State) {
    for len(history) > 0 {
        item := pop(history)
        delete(item.data)
    }
    clear(history)
}

push_history_state :: proc(
    buffer: ^Buffer, history: ^[dynamic]History_State,
) -> mem.Allocator_Error {
    item := History_State{
        cursor    = buffer.cursor,
        data      = slice.clone(buffer.data, buffer.allocator),
        gap_end   = buffer.gap_end,
        gap_start = buffer.gap_start,
    }

    append(history, item) or_return
    return nil
}

check_buffer_history_state :: proc(buffer: ^Buffer) {
    clear_history(&buffer.redo)

    if time.tick_diff(buffer.last_edit_time, buffer.current_time) > buffer.undo_timeout {
        log.debugf("Creating a new history state for buffer {0}", buffer.name)
        push_history_state(buffer, &buffer.undo)
    }

    buffer.last_edit_time = buffer.current_time
}

buffer_save :: proc(buffer: ^Buffer) {
    if buffer.modified {
        log.debugf("Saving {0}", buffer.name)
        changed := sanitize_buffer(buffer)
        str := string(buffer.builder.buf[:])
        err := os.write_entire_file_or_err(buffer.filepath, transmute([]u8)str)

        if err != nil {
            log.errorf("Error saving buffer {0}", buffer.name)
            return
        }

        buffer.dirty = changed
    } else {
        log.debugf("Nothing to save in {0}", buffer.name)
    }
}

sanitize_buffer :: proc(buffer: ^Buffer) -> (changed: bool) {
    assert(buffer.builder != nil)

    LF_COUNT :: 2
    initial_cursor_pos := buffer.cursor
    str := string(buffer.builder.buf[:])
    counting_line_endings := true
    line_endings := 0
    changed = false

    #reverse for r, index in str {
        if counting_line_endings && r == '\n' {
            line_endings += 1
        } else {
            counting_line_endings = false
        }

        if r == '\r' {
            remove(buffer, index, 1)
            changed = true
        }
    }

    if line_endings < LF_COUNT {
        for ; line_endings > 0; line_endings -= 1 {
            insert(buffer, buffer_len(buffer), rune('\n'))
            changed = true
        }
    } else {
        remove(buffer, buffer_len(buffer), LF_COUNT - line_endings)
        changed = true
    }

    buffer.cursor = clamp(initial_cursor_pos, 0, buffer_len(buffer) - 1)
    rebuild_string_buffer(buffer)
    return
}

flush_entire_buffer :: proc(buffer: ^Buffer) {
    flush_range(buffer, 0, buffer_len(buffer))
}

flush_range :: proc(buffer: ^Buffer, start, end: int) {
    left, right := get_strings(buffer)
    assert(start >= 0, "invalid start position")
    assert(end <= buffer_len(buffer), "invalud end position")

    left_len := len(left)

    if end <= left_len {
        strings.write_string(buffer.builder, left[start:end])
    } else if start >= left_len {
        strings.write_string(buffer.builder, right[start - left_len:end - left_len])
    } else {
        strings.write_string(buffer.builder, left[start:])
        strings.write_string(buffer.builder, right[:end - left_len])
    }
}

get_strings :: proc(buffer: ^Buffer) -> (left, right: string) {
    left = string(buffer.data[:buffer.gap_start])
    right = string(buffer.data[buffer.gap_end:])
    return
}

rebuild_string_buffer :: proc(buffer: ^Buffer) {
    strings.builder_reset(buffer.builder)
    strings.builder_init_len_cap(buffer.builder, buffer_len(buffer), len(buffer.data))
    flush_entire_buffer(buffer)
}

// Deletes X characters. If positive, deletes forward
remove :: proc(buffer: ^Buffer, pos: int, count: int) {
    check_buffer_history_state(buffer)
    chars_to_remove := abs(count)
    effective_pos := pos

    if count < 0 {
        effective_pos = max(0, effective_pos - chars_to_remove)
        buffer.cursor = max(0, buffer.cursor - chars_to_remove)
    }

    move_gap(buffer, effective_pos)
    buffer.dirty = true
}

insert :: proc{
    insert_char,
    insert_rune,
    insert_array,
    insert_string,
}

// Inserts u8 character at pos
insert_char :: proc(buffer: ^Buffer, pos: int, char: u8) {
    check_buffer_history_state(buffer)
    conditionally_grow_buffer(buffer, 1)
    move_gap(buffer, pos)
    buffer.data[buffer.gap_start] = char
    buffer.gap_start += 1
    buffer.cursor += 1
    buffer.dirty = true
}

// Inserts array at pos
insert_array :: proc(buffer: ^Buffer, pos: int, array: []u8) {
    check_buffer_history_state(buffer)
    conditionally_grow_buffer(buffer, len(array))
    move_gap(buffer, pos)
    copy_slice(buffer.data[buffer.gap_start:], array)
    buffer.gap_start += len(array)
    buffer.cursor += len(array)
    buffer.dirty = true
}

// Inserts rune (unicode char) at pos
insert_rune :: proc(buffer: ^Buffer, pos: int, r: rune) {
    bytes, _ := utf8.encode_rune(r)
    insert_array(buffer, pos, bytes[:])
}

// Inserts string at pos
insert_string :: proc(buffer: ^Buffer, pos: int, str: string) {
    insert_array(buffer, pos, transmute([]u8)str)
}

buffer_len :: proc(buffer: ^Buffer) -> int {
    gap := buffer.gap_end - buffer.gap_start
    return len(buffer.data) - gap
}

move_gap :: proc(buffer: ^Buffer, pos: int) {
    pos := clamp(pos, 0, buffer_len(buffer))

    if pos == buffer.gap_start {
        return
    }

    if buffer.gap_start < pos {
        delta := pos - buffer.gap_start
        mem.copy(&buffer.data[buffer.gap_start], &buffer.data[buffer.gap_end], delta)
        buffer.gap_start += delta
        buffer.gap_end += delta
    } else {
        delta := buffer.gap_start - pos
        mem.copy(&buffer.data[buffer.gap_end - delta],
                 &buffer.data[buffer.gap_start - delta], delta)
        buffer.gap_start -= delta
        buffer.gap_end -= delta
    }
}

conditionally_grow_buffer :: proc(buffer: ^Buffer, count: int) {
    gap_len := buffer.gap_end - buffer.gap_start

    if gap_len < count {
        required_new_data_array_size := count + len(buffer.data) - gap_len
        new_data_len := max(2 * len(buffer.data), required_new_data_array_size)

        move_gap(buffer, len(buffer.data) - gap_len)
        new_data_array := make([]u8, new_data_len, buffer.allocator)
        copy_slice(new_data_array, buffer.data[:buffer.gap_end])
        delete(buffer.data)
        buffer.data = new_data_array
        buffer.gap_end = len(new_data_array)
    }
}
