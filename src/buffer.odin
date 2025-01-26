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

History_State :: struct {
    cursors:   []Cursor,
    cursor:    int,
    data:      []byte,
    gap_end:   int,
    gap_start: int,
}

Cursor :: [2]int

Buffer :: struct {
    allocator:            runtime.Allocator,

    cursors:              [dynamic]Cursor,
    marking:              bool,

    cursor:               int,
    data:                 []byte,
    dirty:                bool,
    was_dirty_last_frame: bool,
    gap_end:              int,
    gap_start:            int,
    single_line:          bool,
    lines:                [dynamic]int,

    enable_history:       bool,
    redo:                 [dynamic]History_State,
    undo:                 [dynamic]History_State,
    history_limit:        int,
    current_time:         time.Tick,
    last_edit_time:       time.Tick,
    undo_timeout:         time.Duration,

    builder:              ^strings.Builder,

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
        cursors        = make([dynamic]Cursor, 1, 1),
        cursor         = 0,
        data           = make([]byte, bytes, allocator),
        dirty          = false,
        enable_history = true,
        gap_start      = 0,
        gap_end        = bytes,
        lines          = make([dynamic]int, 0, 32),
        major_mode     = .Fundamental,
        name           = strings.clone(name),
        redo           = make([dynamic]History_State, 0, 5, allocator),
        undo           = make([dynamic]History_State, 0, 5, allocator),
        undo_timeout   = undo_timeout,
    }
    recalculate_lines(&b, b.data[:])
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
        cursor         = 0,
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
    result.cursor = 0
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

buffer_begin :: proc(b: ^Buffer, builder: ^strings.Builder) {
    assert(builder != nil)
    assert(b.dirty == false)
    profiling_start("buffer_begin")

    b.builder = builder
    update_buffer_time(b)

    if b.was_dirty_last_frame {
        b.was_dirty_last_frame = false
        refresh_string_buffer(b)
        recalculate_lines(b, b.builder.buf[:])
    }

    profiling_end()
}

buffer_end :: proc(b: ^Buffer) {
    b.builder = nil

    if b.dirty {
        b.dirty = false
        b.was_dirty_last_frame = true
    }
}

buffer_destroy :: proc(buffer: ^Buffer) {
    clear_history(&buffer.undo)
    clear_history(&buffer.redo)
    delete(buffer.cursors)
    delete(buffer.data)
    delete(buffer.lines)
    delete(buffer.name)
    delete(buffer.redo)
    delete(buffer.undo)
    buffer.builder = nil
}

update_buffer_time :: proc(buffer: ^Buffer) {
    if buffer.enable_history {
        buffer.current_time = time.tick_now()
	    if buffer.undo_timeout <= 0 {
		    buffer.undo_timeout = UNDO_DEFAULT_TIMEOUT
	    }
    }
}

recalculate_lines :: proc(buffer: ^Buffer, buf: []u8) {
    clear(&buffer.lines)
    append(&buffer.lines, 0)

    for c, index in buf {
        if buf[index] == '\n' {
            append(&buffer.lines, index + 1)
        }
    }
}

is_between_line :: #force_inline proc(buffer: ^Buffer, line, pos: int) -> bool {
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

get_line_index :: #force_inline proc(buffer: ^Buffer, pos: int) -> (line: int) {
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

Cursor_Translation :: enum {
    DOWN, RIGHT, LEFT, UP,
    BUFFER_START,
    BUFFER_END,
    LINE_START,
    LINE_END,
    WORD_START,
    WORD_END,
}

get_current_cursor_head :: #force_inline proc(b: ^Buffer) -> int {
    return b.cursors[len(b.cursors) - 1][0]
}

translate :: proc(b: ^Buffer, t: Cursor_Translation) -> (pos: int) {
    assert(b.builder != nil)
    pos = b.cursor
    //pos = get_current_cursor_head(b)
    buf := b.builder.buf[:]
    line_index := get_line_index(b, pos)
    line_start_start := get_line_start(b, line_index)
    offset_from_bol := pos - line_start_start

    switch t {
    case .DOWN:
        if is_last_line(b, line_index) { return }

        next_line_index := line_index + 1
        next_line_start := get_line_start(b, next_line_index)

        if is_between_line(b, next_line_index, next_line_start + offset_from_bol) {
            pos = next_line_start + offset_from_bol
        } else {
            pos = get_line_end(b, next_line_index)
        }
    case .LEFT:
        pos -= 1
        for pos > 0 && is_continuation_byte(buf[pos]) { pos -= 1 }
    case .RIGHT:
        pos += 1
        for pos < len(buf) && is_continuation_byte(buf[pos]) { pos += 1 }
    case .UP:
        if line_index == 0 { return }

        prev_line_index := line_index - 1
        prev_line_start := get_line_start(b, prev_line_index)

        if is_between_line(b, prev_line_index, prev_line_start + offset_from_bol) {
            pos = prev_line_start + offset_from_bol
        } else {
            pos = get_line_end(b, prev_line_index)
        }
    case .BUFFER_START:
        pos = 0
    case .BUFFER_END:
        pos = len(buf)
    case .LINE_START:
        if pos == line_start_start {
            for pos < len(buf) && is_whitespace(buf[pos]) { pos += 1 }
        } else {
            pos = line_start_start
        }
    case .LINE_END:
        for pos < len(buf) && !is_newline(buf[pos]) { pos += 1 }
    case .WORD_START:
        // TODO: WORD_START and WORD_END should actually figure out if the
        // characters in point form a word or not, and the skip over them.
        // Right now basically is taking "WORD" as a regular english word,
        // even when there's characters like underscore or hyphen in the middle.
        for pos > 0 && is_whitespace(buf[pos - 1])  { pos -= 1 }
        for pos > 0 && !is_whitespace(buf[pos - 1]) { pos -= 1 }
    case .WORD_END:
        for pos < len(buf) && is_whitespace(buf[pos])  { pos += 1 }
        for pos < len(buf) && !is_whitespace(buf[pos]) { pos += 1 }
    }

    return clamp(pos, 0, len(buf))
}

delete_to :: proc(b: ^Buffer, t: Cursor_Translation) {
    pos := translate(b, t)
    remove(b, b.cursor, pos - b.cursor)
}

move_to :: proc(b: ^Buffer, t: Cursor_Translation) {
    // TODO: Manage multiple cursors
    has_selection :: proc(b: ^Buffer) -> bool {
        return false
    }

    if has_selection(b) {
        // TODO: make selection logic
    } else {
        pos := translate(b, t)
        b.cursor = pos
        // b.cursors[0] = { pos, pos }
    }
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

        buffer.cursor    = item.cursor
        buffer.gap_end   = item.gap_end
        buffer.gap_start = item.gap_start

        delete(buffer.cursors)
        delete(buffer.data)
        buffer.cursors = slice.clone_to_dynamic(item.cursors, buffer.allocator)
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
        cursors   = slice.clone(buffer.cursors[:], buffer.allocator),
        cursor    = buffer.cursor,
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

buffer_save :: proc(buffer: ^Buffer, data: []byte) {
    if buffer.modified {
        log.debugf("Saving {0}", buffer.name)
        // sanitize_buffer(buffer)
        err := os.write_entire_file_or_err(buffer.filepath, data)

        if err != nil {
            log.errorf("Error saving buffer {0}", buffer.name)
            return
        }

        // buffer.dirty = changed
        buffer.modified = false
    } else {
        log.debugf("Nothing to save in {0}", buffer.name)
    }
}

sanitize_buffer :: proc(buffer: ^Buffer) {
    assert(buffer.builder != nil)

    LF_COUNT :: 1
    initial_cursor_pos := buffer.cursor
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

    buffer.cursor = clamp(initial_cursor_pos, 0, buffer_len(buffer) - 1)

    if changed {
        refresh_string_buffer(buffer)
    }
}

flush_entire_buffer :: proc(buffer: ^Buffer) {
    flush_range(buffer, 0, buffer_len(buffer))
}

flush_range :: proc(buffer: ^Buffer, start, end: int) {
    left, right := buffer_get_strings(buffer)
    assert(start >= 0, "invalid start position")
    assert(end <= buffer_len(buffer), "invalud end position")
    assert(buffer.builder != nil)

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

buffer_get_strings :: proc(buffer: ^Buffer) -> (left, right: string) {
    left  = string(buffer.data[:buffer.gap_start])
    right = string(buffer.data[buffer.gap_end:])
    return
}

refresh_string_buffer :: proc(buffer: ^Buffer) {
    assert(buffer.builder != nil)
    strings.builder_reset(buffer.builder)
    flush_entire_buffer(buffer)
}

// Deletes X characters. If positive, deletes forward
// TODO: Support UTF8
remove :: proc(buffer: ^Buffer, pos: int, count: int) {
    check_buffer_history_state(buffer)
    chars_to_remove := abs(count)
    effective_pos := pos

    if count < 0 {
        effective_pos = max(0, effective_pos - chars_to_remove)
        buffer.cursor = effective_pos
    }

    move_gap(buffer, effective_pos)
    buffer.gap_end = min(buffer.gap_end + chars_to_remove, len(buffer.data))
    buffer.dirty = true
    buffer.modified = true
}

insert :: proc{
    insert_char,
    insert_rune,
    insert_array,
    insert_string,
}

// Inserts u8 character at pos
insert_char :: proc(buffer: ^Buffer, pos: int, char: u8) {
    assert(pos >= 0 && pos <= buffer_len(buffer))
    check_buffer_history_state(buffer)
    conditionally_grow_buffer(buffer, 1)
    move_gap(buffer, pos)
    buffer.data[buffer.gap_start] = char
    buffer.gap_start += 1
    buffer.cursor += 1
    buffer.dirty = true
    buffer.modified = true
}

// Inserts array at pos
insert_array :: proc(buffer: ^Buffer, pos: int, array: []byte) {
    assert(pos >= 0 && pos <= buffer_len(buffer))
    check_buffer_history_state(buffer)
    conditionally_grow_buffer(buffer, len(array))
    move_gap(buffer, pos)
    copy_slice(buffer.data[buffer.gap_start:], array)
    buffer.gap_start += len(array)
    buffer.cursor += len(array)
    buffer.dirty = true
    buffer.modified = true
}

// Inserts rune (unicode char) at pos
insert_rune :: proc(buffer: ^Buffer, pos: int, r: rune) {
    bytes, _ := utf8.encode_rune(r)
    insert_array(buffer, pos, bytes[:])
}

// Inserts string at pos
insert_string :: proc(buffer: ^Buffer, pos: int, str: string) {
    insert_array(buffer, pos, transmute([]byte)str)
}

buffer_len :: proc(buffer: ^Buffer) -> int {
    gap := buffer.gap_end - buffer.gap_start
    return len(buffer.data) - gap
}

move_gap :: proc(buffer: ^Buffer, pos: int) {
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
