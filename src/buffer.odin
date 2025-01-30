package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:thread"
import "core:time"
import "core:unicode/utf8"

UNDO_DEFAULT_TIMEOUT :: 300 * time.Millisecond

Buffer_Cursor :: int

History_State :: struct {
    cursor:    Buffer_Cursor,
    data:      []byte,
    gap_end:   int,
    gap_start: int,
}

Buffer :: struct {
    allocator:            runtime.Allocator,
    internal:             bool,

    cursor:               Buffer_Cursor,
    data:                 []byte,
    str:                  string,
    dirty:                bool,
    was_dirty_last_frame: bool,
    gap_end:              Buffer_Cursor,
    gap_start:            Buffer_Cursor,
    lines:                [dynamic]int,

    enable_history:       bool,
    redo:                 [dynamic]History_State,
    undo:                 [dynamic]History_State,
    history_limit:        int,
    current_time:         time.Tick,
    last_edit_time:       time.Tick,
    undo_timeout:         time.Duration,

    filepath:             string,
    major_mode:           Major_Mode,
    name:                 string,
    readonly:             bool,
    modified:             bool,
    crlf:                 bool,
}

buffer_init :: proc(
    name: string,
    bytes: int,
    undo_timeout := UNDO_DEFAULT_TIMEOUT,
    allocator := context.allocator,
) -> Buffer {
    b := Buffer{
        allocator      = allocator,

        data           = make([]byte, bytes, allocator),
        str            = "",
        dirty          = false,
        gap_start      = 0,
        gap_end        = bytes,
        lines          = make([dynamic]int, 0, 32),

        enable_history = true,
        redo           = make([dynamic]History_State, 0, 5, allocator),
        undo           = make([dynamic]History_State, 0, 5, allocator),
        undo_timeout   = undo_timeout,

        major_mode     = .Fundamental,
        name           = strings.clone(name),
    }
    recalculate_lines(&b)
    return b
}

create_buffer :: proc(
    name: string,
    bytes: int,
    undo_timeout := UNDO_DEFAULT_TIMEOUT,
    allocator := context.allocator,
) -> ^Buffer {
    append(&bragi.buffers, Buffer{
        allocator      = allocator,
        data           = make([]byte, bytes, allocator),
        dirty          = false,
        enable_history = true,
        gap_start      = 0,
        gap_end        = bytes,
        lines          = make([dynamic]int, 0, 32),
        major_mode     = .Fundamental,
        name           = strings.clone(name),
        redo           = make([dynamic]History_State, 0, 5),
        undo           = make([dynamic]History_State, 0, 5),
        undo_timeout   = undo_timeout,
    })

    result := &bragi.buffers[len(bragi.buffers) - 1]

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
    result.modified = false
    result.cursor = 0

    // TODO: Because in debug I'm opening a file when running Bragi, I need
    // this to be temporarily false
    result.dirty = false
    result.was_dirty_last_frame = true

    return result
}

get_or_create_buffer :: proc(
    name: string,
    bytes: int,
    undo_timeout := UNDO_DEFAULT_TIMEOUT,
    allocator := context.allocator,
) -> ^Buffer {
    for &b in bragi.buffers {
        if b.name == name {
            return &b
        }
    }

    return create_buffer(name, bytes, undo_timeout, allocator)
}

buffer_begin :: proc(b: ^Buffer) {
    assert(b.dirty == false)
    profiling_start("buffer_begin")

    update_buffer_time(b)

    if b.was_dirty_last_frame {
        b.was_dirty_last_frame = false
        refresh_string_buffer(b)
        recalculate_lines(b)
    }

    profiling_end()
}

buffer_end :: proc(b: ^Buffer) {
    if b.dirty {
        b.dirty = false
        b.was_dirty_last_frame = true
    }
}

buffer_destroy :: proc(b: ^Buffer) {
    clear_history(&b.undo)
    clear_history(&b.redo)
    delete(b.data)
    delete(b.lines)
    delete(b.name)
    delete(b.redo)
    delete(b.str)
    delete(b.undo)
}

update_buffer_time :: proc(b: ^Buffer) {
    if b.enable_history {
        b.current_time = time.tick_now()
	    if b.undo_timeout <= 0 {
		    b.undo_timeout = UNDO_DEFAULT_TIMEOUT
	    }
    }
}

recalculate_lines :: proc(b: ^Buffer) {
    buf := transmute([]u8)b.str
    clear(&b.lines)
    append(&b.lines, 0)

    for c, index in buf {
        if buf[index] == '\n' {
            append(&b.lines, index + 1)
        }
    }
}

is_between_line :: #force_inline proc(b: ^Buffer, line, pos: Buffer_Cursor) -> bool {
    if line + 1 < len(b.lines) {
        current_bol := get_line_start(b, line)
        next_bol := get_line_start(b, line + 1)
        return pos >= current_bol && pos < next_bol
    }

    return true
}

is_last_line :: #force_inline proc(buffer: ^Buffer, line: int) -> bool {
    return line == len(buffer.lines) - 1
}

get_line_end :: #force_inline proc(b: ^Buffer, line: int) -> int {
    if line + 1 < len(b.lines) {
        offset := get_line_start(b, line + 1)
        return offset - 1
    }

    return b.lines[line]
}

get_line_index :: #force_inline proc(b: ^Buffer, pos: Buffer_Cursor) -> (line: int) {
    for offset, index in b.lines {
        if is_between_line(b, index, pos) {
            line = index
            break
        }
    }

    return
}

get_line_length :: #force_inline proc(b: ^Buffer, line: int) -> (length: int) {
    return get_line_end(b, line) - get_line_start(b, line)
}

get_line_start :: #force_inline proc(b: ^Buffer, line: int) -> (offset: int) {
    assert(line < len(b.lines))
    return b.lines[line]
}

get_line_start_after_indent :: #force_inline proc(b: ^Buffer, line: int) -> (offset: int) {
    assert(line < len(b.lines))
    offset = b.lines[line]

    for offset < get_line_end(b, line) && is_whitespace(b.str[offset]) {
        offset +=1
    }

    return
}

get_buffer_status :: proc(b: ^Buffer) -> (status: string) {
    switch {
    case b.modified: status = "*"
    case b.readonly: status = "%"
    case           : status = "-"
    }

    return
}

clear_history :: proc(history: ^[dynamic]History_State) {
    for len(history) > 0 {
        item := pop(history)
        delete(item.data)
    }
    clear(history)
}

undo_redo :: proc(b: ^Buffer, undo, redo: ^[dynamic]History_State) -> bool {
    if len(undo) > 0 {
        push_history_state(b, redo)
        item := pop(undo)

        b.cursor    = item.cursor
        b.gap_end   = item.gap_end
        b.gap_start = item.gap_start

        delete(b.data)
        b.data = slice.clone(item.data, b.allocator)
        delete(item.data)
        b.dirty = true
        b.modified = true
        return true
    }

    return false
}

push_history_state :: proc(b: ^Buffer, history: ^[dynamic]History_State) -> mem.Allocator_Error {
    item := History_State{
        cursor    = b.cursor,
        data      = slice.clone(b.data, b.allocator),
        gap_end   = b.gap_end,
        gap_start = b.gap_start,
    }

    append(history, item) or_return

    // TODO: Keep history length to 5 temporarily
    for len(history) > 5 {
        delete(history[0].data)
        ordered_remove(history, 0)
    }

    return nil
}

check_buffer_history_state :: proc(b: ^Buffer) {
    if b.enable_history {
        clear_history(&b.redo)

        if time.tick_diff(b.last_edit_time, b.current_time) > b.undo_timeout {
            log.debugf("Creating a new history state for buffer {0}", b.name)
            push_history_state(b, &b.undo)
        }

        b.last_edit_time = b.current_time
    }
}

buffer_save :: proc(b: ^Buffer) {
    if b.modified {
        log.debugf("Saving {0}", b.name)
        // sanitize_buffer(buffer)
        err := os.write_entire_file_or_err(b.filepath, transmute([]u8)b.str)

        if err != nil {
            log.errorf("Error saving buffer {0}", b.name)
            return
        }

        // buffer.dirty = changed
        b.modified = false
    } else {
        log.debugf("Nothing to save in {0}", b.name)
    }
}

sanitize_buffer :: proc(buffer: ^Buffer) {
    LF_COUNT :: 1
    initial_cursor_pos := 0
    line_endings := 0
    changed := false

    for x := len(buffer.data) - 1; x > 0; x -= 1 {
        if buffer.data[x] != '\n' { break }
        line_endings += 1
    }

    if line_endings < LF_COUNT {
        for ; line_endings > 0; line_endings -= 1 {
            insert_char(buffer, buffer_len(buffer), '\n')
            changed = true
        }
    } else if line_endings > LF_COUNT {
        remove(buffer, buffer_len(buffer), LF_COUNT - line_endings)
        changed = true
    }

    if changed {
        refresh_string_buffer(buffer)
    }
}

flush_range :: proc(b: ^Buffer, start, end: int) {
    builder := strings.builder_make(context.temp_allocator)
    left, right := buffer_get_strings(b)
    assert(start >= 0, "invalid start position")
    assert(end <= buffer_len(b), "invalud end position")

    left_len := len(left)

    if end <= left_len {
        strings.write_string(&builder, left[start:end])
    } else if start >= left_len {
        strings.write_string(&builder, right[start - left_len:end - left_len])
    } else {
        strings.write_string(&builder, left[start:])
        strings.write_string(&builder, right[:end - left_len])
    }

    b.str = strings.clone(strings.to_string(builder))
}

buffer_get_strings :: proc(buffer: ^Buffer) -> (left, right: string) {
    left  = string(buffer.data[:buffer.gap_start])
    right = string(buffer.data[buffer.gap_end:])
    return
}

refresh_string_buffer :: proc(b: ^Buffer) {
    delete(b.str)
    flush_range(b, 0, buffer_len(b))
}

// Deletes X characters. If positive, deletes forward
// TODO: Support UTF8
remove :: proc(b: ^Buffer, pos: Buffer_Cursor, count: int) -> int {
    b.cursor = pos
    check_buffer_history_state(b)
    chars_to_remove := abs(count)
    effective_pos := pos

    if count < 0 {
        effective_pos = max(0, effective_pos - chars_to_remove)
        b.cursor = effective_pos
    }

    move_gap(b, effective_pos)
    b.gap_end = min(b.gap_end + chars_to_remove, len(b.data))
    b.dirty = true
    b.modified = true
    return effective_pos - pos
}

insert :: proc{
    insert_char,
    insert_rune,
    insert_array,
    insert_string,
}

// Inserts u8 character at pos
insert_char :: proc(b: ^Buffer, pos: Buffer_Cursor, char: u8) -> int {
    assert(pos >= 0 && pos <= buffer_len(b))
    b.cursor = pos
    check_buffer_history_state(b)
    conditionally_grow_buffer(b, 1)
    move_gap(b, pos)
    b.data[b.gap_start] = char
    b.gap_start += 1
    b.cursor += 1
    b.dirty = true
    b.modified = true
    return 1
}

// Inserts array at pos
insert_array :: proc(b: ^Buffer, pos: Buffer_Cursor, array: []byte) -> int {
    assert(pos >= 0 && pos <= buffer_len(b))
    b.cursor = pos
    check_buffer_history_state(b)
    conditionally_grow_buffer(b, len(array))
    move_gap(b, pos)
    copy_slice(b.data[b.gap_start:], array)
    b.gap_start += len(array)
    b.cursor += len(array)
    b.dirty = true
    b.modified = true
    return len(array)
}

// Inserts rune (unicode char) at pos
insert_rune :: proc(b: ^Buffer, pos: Buffer_Cursor, r: rune) -> int {
    bytes, _ := utf8.encode_rune(r)
    return insert_array(b, pos, bytes[:])
}

// Inserts string at pos
insert_string :: proc(b: ^Buffer, pos: Buffer_Cursor, str: string) -> int {
    return insert_array(b, pos, transmute([]byte)str)
}

buffer_len :: proc(b: ^Buffer) -> int {
    gap := b.gap_end - b.gap_start
    return len(b.data) - gap
}

move_gap :: proc(b: ^Buffer, pos: Buffer_Cursor) {
    pos := clamp(pos, 0, buffer_len(b))

    if pos == b.gap_start { return }

    if b.gap_start < pos {
        delta := pos - b.gap_start
        mem.copy(&b.data[b.gap_start], &b.data[b.gap_end], delta)
        b.gap_start += delta
        b.gap_end += delta
    } else {
        delta := b.gap_start - pos
        mem.copy(&b.data[b.gap_end - delta],
                 &b.data[b.gap_start - delta], delta)
        b.gap_start -= delta
        b.gap_end -= delta
    }
}

conditionally_grow_buffer :: proc(b: ^Buffer, count: int) {
    gap_len := b.gap_end - b.gap_start

    if gap_len < count {
        required_new_data_array_size := count + len(b.data) - gap_len
        new_data_len := max(2 * len(b.data), required_new_data_array_size)

        move_gap(b, len(b.data) - gap_len)
        new_data_array := make([]byte, new_data_len, b.allocator)
        copy_slice(new_data_array, b.data[:b.gap_end])
        delete(b.data)
        b.data = new_data_array
        b.gap_end = len(b.data)
    }
}
