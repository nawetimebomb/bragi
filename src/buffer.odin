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
import "tokenizer"

UNDO_DEFAULT_TIMEOUT :: 300 * time.Millisecond

Buffer_Cursor :: int
Line :: distinct [2]int

History_State :: struct {
    cursor:    Buffer_Cursor,
    data:      []byte,
    gap_end:   int,
    gap_start: int,
}

Buffer :: struct {
    allocator:            runtime.Allocator,

    cursor:               Buffer_Cursor,
    data:                 []byte,
    dirty:                bool,
    gap_end:              Buffer_Cursor,
    gap_start:            Buffer_Cursor,
    lines:                [dynamic]Line,

    str:                  string,
    tokens:               []tokenizer.Token_Kind,

    enable_history:       bool,
    redo:                 [dynamic]History_State,
    undo:                 [dynamic]History_State,
    history_limit:        int,
    current_time:         time.Tick,
    last_edit_time:       time.Tick,
    undo_timeout:         time.Duration,

    status:               string,
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
        lines          = make([dynamic]Line, 0, 16),

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
    append(&open_buffers, Buffer{
        allocator      = allocator,
        data           = make([]byte, bytes, allocator),
        dirty          = false,
        enable_history = true,
        gap_start      = 0,
        gap_end        = bytes,
        lines          = make([dynamic]Line, 0, 16),
        major_mode     = .Fundamental,
        name           = strings.clone(name),
        redo           = make([dynamic]History_State, 0, 5),
        undo           = make([dynamic]History_State, 0, 5),
        undo_timeout   = undo_timeout,
    })

    result := &open_buffers[len(open_buffers) - 1]

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
    result.filepath = strings.clone(filepath)
    result.major_mode = find_major_mode(extension)

    insert(result, 0, data)
    result.modified = false
    result.cursor = 0
    result.dirty = true


    return result
}

get_or_create_buffer :: proc(
    name: string,
    bytes: int,
    undo_timeout := UNDO_DEFAULT_TIMEOUT,
    allocator := context.allocator,
) -> ^Buffer {
    for &b in open_buffers {
        if b.name == name {
            return &b
        }
    }

    return create_buffer(name, bytes, undo_timeout, allocator)
}

buffer_update :: proc(b: ^Buffer) {
    update_buffer_time(b)

    if b.dirty {
        b.dirty = false
        b.status = get_buffer_status(b)

        recalculate_lines(b)
        refresh_string_buffer(b)
        maybe_tokenize_buffer(b)
    }
}

buffer_destroy :: proc(b: ^Buffer) {
    clear_history(&b.undo)
    clear_history(&b.redo)
    delete(b.data)
    delete(b.filepath)
    delete(b.lines)
    delete(b.name)
    delete(b.redo)
    delete(b.str)
    delete(b.tokens)
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
    profiling_start("buffer.odin:recalculate_lines")
    left, right := buffer_get_strings(b)

    clear(&b.lines)
    append(&b.lines, Line{0, 0})

	for index := 0; index < len(left); index += 1 {
		if left[index] == '\n' {
            eocl := index
            bonl := eocl + 1
            last_line_index := len(b.lines) - 1
            b.lines[last_line_index][1] = eocl
            append(&b.lines, Line{bonl, bonl})
        }
	}

	for index := 0; index < len(right); index += 1 {
		if right[index] == '\n' {
            eocl := len(left) + index
            bonl := eocl + 1
            last_line_index := len(b.lines) - 1
            b.lines[last_line_index][1] = eocl
            append(&b.lines, Line{bonl, bonl})
        }
	}

    b.lines[len(b.lines) - 1][1] = buffer_len(b)
    profiling_end()
}

maybe_tokenize_buffer :: proc(b: ^Buffer) {
    profiling_start("buffer.odin:maybe_tokenize_buffer")
    if b.major_mode == .Fundamental {
        // We don't tokenize Fundamental mode
        return
    }

    tokenize_proc: #type proc(^string) -> []tokenizer.Token_Kind

    delete(b.tokens)

    #partial switch b.major_mode {
        case .Bragi: log.error("not implemented")
        case .Odin:  tokenize_proc = tokenizer.tokenize_odin
    }

    b.tokens = tokenize_proc(&b.str)

    profiling_end()
}

is_between_line :: #force_inline proc(b: ^Buffer, line, pos: Buffer_Cursor) -> bool {
    assert(line < len(b.lines))
    start, end := get_line_boundaries(b, line)
    return pos >= start && pos <= end
}

is_last_line :: #force_inline proc(b: ^Buffer, line: int) -> bool {
    assert(line < len(b.lines))
    return line == len(b.lines) - 1
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

get_line_boundaries :: #force_inline proc(b: ^Buffer, line: int) -> (start, end: int) {
    assert(line < len(b.lines))
    boundaries := b.lines[line]
    return boundaries[0], boundaries[1]
}

get_line_length :: #force_inline proc(b: ^Buffer, line: int) -> (length: int) {
    assert(line < len(b.lines))
    start, end := get_line_boundaries(b, line)
    return end - start
}

get_line_start_after_indent :: #force_inline proc(b: ^Buffer, line: int) -> (offset: int) {
    assert(line < len(b.lines))
    bol, eol := get_line_boundaries(b, line)
    offset = bol

    for offset < eol && is_whitespace(b.str[offset]) {
        offset +=1
    }

    return
}

get_buffer_status :: proc(b: ^Buffer) -> (status: string) {
    switch {
    case b.modified && b.readonly:
        status = "%*"
    case b.modified:
        status = "**"
    case b.readonly:
        status = "%%"
    case :
        status = "--"
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
        err := os.write_entire_file_or_err(b.filepath, transmute([]byte)b.str)

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

buffer_get_strings :: proc(buffer: ^Buffer) -> (left, right: string) {
    left  = string(buffer.data[:buffer.gap_start])
    right = string(buffer.data[buffer.gap_end:])
    return
}

refresh_string_buffer :: proc(b: ^Buffer) {
    profiling_start("buffer.odin:refresh_string_buffer")
    builder := strings.builder_make(context.temp_allocator)
    start := 0
    end := buffer_len(b)
    left, right := buffer_get_strings(b)

    left_len := len(left)

    if end <= left_len {
        strings.write_string(&builder, left[start:end])
    } else if start >= left_len {
        strings.write_string(&builder, right[start - left_len:end - left_len])
    } else {
        strings.write_string(&builder, left[start:])
        strings.write_string(&builder, right[:end - left_len])
    }

    delete(b.str)
    b.str = strings.clone(strings.to_string(builder))
    profiling_end()
}

rune_at :: #force_inline proc(b: ^Buffer, pos: Buffer_Cursor) -> rune {
	left, right := buffer_get_strings(b)

	if pos < len(left) {
		return rune(left[pos])
	} else {
		return rune(right[pos - len(left)])
	}
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
insert_char :: proc(b: ^Buffer, pos: Buffer_Cursor, char: byte) -> int {
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
