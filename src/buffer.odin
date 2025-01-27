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
    data:      []byte,
    gap_end:   int,
    gap_start: int,
}

Buffer :: struct {
    allocator:            runtime.Allocator,

    marking:              bool,

    data:                 []byte,
    str:                  string,
    dirty:                bool,
    was_dirty_last_frame: bool,
    gap_end:              Buffer_Cursor,
    gap_start:            Buffer_Cursor,
    single_line:          bool,
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

buffer_destroy :: proc(buffer: ^Buffer) {
    clear_history(&buffer.undo)
    clear_history(&buffer.redo)
    delete(buffer.data)
    delete(buffer.lines)
    delete(buffer.name)
    delete(buffer.str)
    delete(buffer.redo)
    delete(buffer.undo)
}

update_buffer_time :: proc(buffer: ^Buffer) {
    if buffer.enable_history {
        buffer.current_time = time.tick_now()
	    if buffer.undo_timeout <= 0 {
		    buffer.undo_timeout = UNDO_DEFAULT_TIMEOUT
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

is_between_line :: #force_inline proc(buffer: ^Buffer, line, pos: Buffer_Cursor) -> bool {
    if line + 1 < len(buffer.lines) {
        current_bol := get_line_start(buffer, line)
        next_bol := get_line_start(buffer, line + 1)
        return pos >= current_bol && pos < next_bol
    }

    return true
}

is_last_line :: #force_inline proc(buffer: ^Buffer, line: int) -> bool {
    return line == len(buffer.lines) - 1
}

get_line_end :: #force_inline proc(buffer: ^Buffer, line: int) -> int {
    if line + 1 < len(buffer.lines) {
        offset := get_line_start(buffer, line + 1)
        return offset - 1
    }

    return buffer.lines[line]
}

get_line_index :: #force_inline proc(buffer: ^Buffer, pos: Buffer_Cursor) -> (line: int) {
    for offset, index in buffer.lines {
        if is_between_line(buffer, index, pos) {
            line = index
            break
        }
    }

    return
}

get_line_start :: #force_inline proc(buffer: ^Buffer, line: int) -> (offset: int) {
    assert(line < len(buffer.lines))
    return buffer.lines[line]
}

get_buffer_status :: proc(buffer: ^Buffer) -> (status: string) {
    switch {
    case buffer.modified: status = "*"
    case buffer.readonly: status = "%"
    case                : status = "-"
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

undo_redo :: proc(buffer: ^Buffer, undo, redo: ^[dynamic]History_State) {
    if len(undo) > 0 {
        push_history_state(buffer, redo)
        item := pop(undo)

        buffer.gap_end   = item.gap_end
        buffer.gap_start = item.gap_start

        delete(buffer.data)
        buffer.data = slice.clone(item.data, buffer.allocator)
        delete(item.data)
        buffer.dirty = true
        buffer.modified = true
    }
}

push_history_state :: proc(
    buffer: ^Buffer, history: ^[dynamic]History_State,
) -> mem.Allocator_Error {
    item := History_State{
        data      = slice.clone(buffer.data, buffer.allocator),
        gap_end   = buffer.gap_end,
        gap_start = buffer.gap_start,
    }

    append(history, item) or_return

    // TODO: Keep history length to 5 temporarily
    for len(history) > 5 {
        delete(history[0].data)
        ordered_remove(history, 0)
    }

    return nil
}

check_buffer_history_state :: proc(buffer: ^Buffer) {
    if buffer.enable_history {
        clear_history(&buffer.redo)

        if time.tick_diff(buffer.last_edit_time, buffer.current_time) > buffer.undo_timeout {
            log.debugf("Creating a new history state for buffer {0}", buffer.name)
            push_history_state(buffer, &buffer.undo)
        }

        buffer.last_edit_time = buffer.current_time
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
remove :: proc(buffer: ^Buffer, pos: Buffer_Cursor, count: int) -> int {
    check_buffer_history_state(buffer)
    chars_to_remove := abs(count)
    effective_pos := pos

    if count < 0 {
        effective_pos = max(0, effective_pos - chars_to_remove)
    }

    move_gap(buffer, effective_pos)
    buffer.gap_end = min(buffer.gap_end + chars_to_remove, len(buffer.data))
    buffer.dirty = true
    buffer.modified = true
    return effective_pos
}

insert :: proc{
    insert_char,
    insert_rune,
    insert_array,
    insert_string,
}

// Inserts u8 character at pos
insert_char :: proc(buffer: ^Buffer, pos: Buffer_Cursor, char: u8) -> int {
    assert(pos >= 0 && pos <= buffer_len(buffer))
    check_buffer_history_state(buffer)
    conditionally_grow_buffer(buffer, 1)
    move_gap(buffer, pos)
    buffer.data[buffer.gap_start] = char
    buffer.gap_start += 1
    buffer.dirty = true
    buffer.modified = true
    return pos + 1
}

// Inserts array at pos
insert_array :: proc(buffer: ^Buffer, pos: Buffer_Cursor, array: []byte) -> int {
    assert(pos >= 0 && pos <= buffer_len(buffer))
    check_buffer_history_state(buffer)
    conditionally_grow_buffer(buffer, len(array))
    move_gap(buffer, pos)
    copy_slice(buffer.data[buffer.gap_start:], array)
    buffer.gap_start += len(array)
    buffer.dirty = true
    buffer.modified = true
    return pos + len(array)
}

// Inserts rune (unicode char) at pos
insert_rune :: proc(buffer: ^Buffer, pos: Buffer_Cursor, r: rune) -> int {
    bytes, _ := utf8.encode_rune(r)
    return insert_array(buffer, pos, bytes[:])
}

// Inserts string at pos
insert_string :: proc(buffer: ^Buffer, pos: Buffer_Cursor, str: string) -> int {
    return insert_array(buffer, pos, transmute([]byte)str)
}

buffer_len :: proc(buffer: ^Buffer) -> int {
    gap := buffer.gap_end - buffer.gap_start
    return len(buffer.data) - gap
}

move_gap :: proc(buffer: ^Buffer, pos: Buffer_Cursor) {
    pos := clamp(pos, 0, buffer_len(buffer))

    if pos == buffer.gap_start { return }

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
        new_data_array := make([]byte, new_data_len, buffer.allocator)
        copy_slice(new_data_array, buffer.data[:buffer.gap_end])
        delete(buffer.data)
        buffer.data = new_data_array
        buffer.gap_end = len(buffer.data)
    }
}
