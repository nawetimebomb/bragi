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

// Ideas on how to improve cursor management:
// cursors should be part of the buffer, so whenever we change the pane buffer, the cursor
// is already in there. We changed this because we were handling input later on.
// We don't really need cursors in panes, we can keep marks in panes though.

UNDO_DEFAULT_TIMEOUT :: 300 * time.Millisecond

Buffer_Cursor :: int

Cursor_Translation :: enum {
    DOWN, RIGHT, LEFT, UP,
    BUFFER_START,
    BUFFER_END,
    LINE_START,
    LINE_END,
    WORD_START,
    WORD_END,
}

Cursor :: struct {
    pos, sel: int,
    col_offset: int,
}

Cursor_Coords :: struct {
    pos, sel: Coords,
}

Range :: struct {
    start, end: int,
}

Coords :: struct {
    line, column: int,
}

History_State :: struct {
    cursors:   []Cursor,
    data:      []byte,
    gap_end:   int,
    gap_start: int,
}

Buffer :: struct {
    allocator:            runtime.Allocator,

    cursors:              [dynamic]Cursor,
    interactive_cursors:  bool,
    data:                 []byte,
    dirty:                bool,
    gap_end:              Buffer_Cursor,
    gap_start:            Buffer_Cursor,
    lines:                [dynamic]Range,

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
        lines          = make([dynamic]Range, 0, 16),

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
        lines          = make([dynamic]Range, 0, 16),
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

    insert_raw(result, 0, data)
    result.modified = false
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

    if len(b.cursors) == 0 { append(&b.cursors, make_cursor()) }

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
    delete(b.cursors)
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
    append(&b.lines, Range{0, 0})

    for index := 0; index < len(left); index += 1 {
        if left[index] == '\n' {
            eocl := index
            bonl := eocl + 1
            last_line_index := len(b.lines) - 1
            b.lines[last_line_index].end = eocl
            append(&b.lines, Range{bonl, bonl})
        }
    }

    for index := 0; index < len(right); index += 1 {
        if right[index] == '\n' {
            eocl := len(left) + index
            bonl := eocl + 1
            last_line_index := len(b.lines) - 1
            b.lines[last_line_index].end = eocl
            append(&b.lines, Range{bonl, bonl})
        }
    }

    b.lines[len(b.lines) - 1].end = buffer_len(b)
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

get_line_boundaries :: #force_inline proc(b: ^Buffer, line: int, loc := #caller_location) -> (start, end: int) {
    log.assertf(line < len(b.lines), "Failed: line: {0}, caller: {1}", line, loc)
    result := b.lines[line]
    return result.start, result.end
}

get_line_text :: #force_inline proc(b: ^Buffer, line: int) -> (result: string) {
    assert(line < len(b.lines))
    start, end := get_line_boundaries(b, line)
    return b.str[start:end]
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
        delete(item.cursors)
        delete(item.data)
    }
    clear(history)
}

undo_redo :: proc(b: ^Buffer, undo, redo: ^[dynamic]History_State) -> bool {
    if len(undo) > 0 {
        push_history_state(b, redo)
        item := pop(undo)

        b.gap_end   = item.gap_end
        b.gap_start = item.gap_start

        delete(b.cursors)
        b.cursors = slice.clone_to_dynamic(item.cursors)
        delete(item.cursors)

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
        cursors   = slice.clone(b.cursors[:], b.allocator),
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

get_byte_at :: #force_inline proc(b: ^Buffer, pos: Buffer_Cursor) -> byte {
	left, right := buffer_get_strings(b)

	if pos < len(left) {
		return left[pos]
	} else {
		return right[pos - len(left)]
	}
}

delete_all_cursors :: proc(b: ^Buffer, new_cursor: Cursor = {}) {
    clear(&b.cursors)
    append(&b.cursors, new_cursor)
}

make_cursor :: proc(pos: int = 0) -> (result: Cursor) {
    result.pos = pos
    result.sel = pos
    result.col_offset = -1
    return
}

promote_cursor_index :: #force_inline proc(b: ^Buffer, cursor_index: int) {
    new_cursor := b.cursors[cursor_index]
    ordered_remove(&b.cursors, cursor_index)
    append(&b.cursors, new_cursor)
}

get_coords :: #force_inline proc(b: ^Buffer, pos: int) -> (result: Coords) {
    result.line = get_line_index(b, pos)
    bol, _ := get_line_boundaries(b, result.line)
    result.column = pos - bol
    return
}

get_last_cursor_pos_as_coords :: #force_inline proc(b: ^Buffer) -> (pos: Coords) {
    return get_coords(b, get_last_cursor_pos(b))
}

get_last_cursor_pos :: #force_inline proc(b: ^Buffer) -> (pos: int) {
    return b.cursors[len(b.cursors) - 1].pos
}

set_last_cursor_pos :: #force_inline proc(b: ^Buffer, pos: int) {
    b.cursors[len(b.cursors) - 1].pos = pos
}

get_offset_from_coords :: proc(b: ^Buffer, coords: Coords) -> (pos: int) {
    bol, _ := get_line_boundaries(b, coords.line)
    return bol + coords.column
}

dwim_last_cursor_col_offset :: proc(b: ^Buffer, new_offset: int) -> (max_offset: int) {
    last_cursor := &b.cursors[len(b.cursors) - 1]

    if new_offset == - 1 {
        last_cursor.col_offset = -1
    } else {
        last_cursor.col_offset = max(last_cursor.col_offset, new_offset)
    }

    return last_cursor.col_offset
}

translate_cursor :: proc(b: ^Buffer, t: Cursor_Translation) -> (pos: int) {
    pos = get_last_cursor_pos(b)
    lines_count := len(b.lines)
    coords := get_coords(b, pos)

    switch t {
    case .DOWN:
        if coords.line < lines_count - 1 {
            coords.line += 1
            coords.column = min(
                dwim_last_cursor_col_offset(b, coords.column),
                get_line_length(b, coords.line),
            )
            pos = get_offset_from_coords(b, coords)
            return
        }
    case .UP:
        if coords.line > 0 {
            coords.line -= 1
            coords.column = min(
                dwim_last_cursor_col_offset(b, coords.column),
                get_line_length(b, coords.line),
            )
            pos = get_offset_from_coords(b, coords)
            return
        }
    case .LEFT:
        pos = max(pos - 1, 0)
        dwim_last_cursor_col_offset(b, -1)
        return
    case .RIGHT:
        pos = min(pos + 1, buffer_len(b))
        dwim_last_cursor_col_offset(b, -1)
        return
    case .BUFFER_START:
        pos = 0
        return
    case .BUFFER_END:
        pos = buffer_len(b)
        return
    case .LINE_START:
        bol, _ := get_line_boundaries(b, coords.line)
        bol_after_indent := get_line_start_after_indent(b, coords.line)
        pos = pos == bol ? bol_after_indent : bol
        return
    case .LINE_END:
        _, eol := get_line_boundaries(b, coords.line)
        pos = eol
        return
    case .WORD_START:
        for pos > 0 && is_whitespace(get_byte_at(b, pos - 1)) { pos -= 1 }
        for pos > 0 && !is_whitespace(get_byte_at(b, pos - 1)) { pos -= 1 }
        return
    case .WORD_END:
        for pos < buffer_len(b) && is_whitespace(get_byte_at(b, pos))  { pos += 1 }
        for pos < buffer_len(b) && !is_whitespace(get_byte_at(b, pos)) { pos += 1}
        return
    }

    return
}

// Deletes X characters. If positive, deletes forward
// TODO: Support UTF8
remove :: proc(b: ^Buffer, pos: Buffer_Cursor, count: int) {
    check_buffer_history_state(b)
    chars_to_remove := abs(count)
    effective_pos := pos

    if count < 0 {
        effective_pos = max(0, effective_pos - chars_to_remove)
    }

    move_gap(b, effective_pos)
    b.gap_end = min(b.gap_end + chars_to_remove, len(b.data))
    b.dirty = true
    b.modified = true
}

insert_char :: proc(b: ^Buffer, char: byte) {
    for &cursor in b.cursors {
        insert_raw(b, cursor.pos, char)
        cursor.pos += 1
        cursor.sel = cursor.pos
        cursor.col_offset = -1
    }
}

insert_string :: proc(b: ^Buffer, str: string) {
    for &cursor in b.cursors {
        insert_raw(b, cursor.pos, str)
        cursor.pos += len(str)
        cursor.sel = cursor.pos
        cursor.col_offset = -1
    }
}

@(private="file")
insert_raw :: proc{
    insert_raw_char,
    insert_raw_rune,
    insert_raw_array,
    insert_raw_string,
}

@(private="file")
insert_raw_char :: proc(b: ^Buffer, pos: Buffer_Cursor, char: byte) {
    assert(pos >= 0 && pos <= buffer_len(b))
    check_buffer_history_state(b)
    conditionally_grow_buffer(b, 1)
    move_gap(b, pos)
    b.data[b.gap_start] = char
    b.gap_start += 1
    b.dirty = true
    b.modified = true
}

@(private="file")
insert_raw_array :: proc(b: ^Buffer, pos: Buffer_Cursor, array: []byte) -> int {
    assert(pos >= 0 && pos <= buffer_len(b))
    check_buffer_history_state(b)
    conditionally_grow_buffer(b, len(array))
    move_gap(b, pos)
    copy_slice(b.data[b.gap_start:], array)
    b.gap_start += len(array)
    b.dirty = true
    b.modified = true
    return len(array)
}

@(private="file")
insert_raw_rune :: proc(b: ^Buffer, pos: Buffer_Cursor, r: rune) -> int {
    bytes, _ := utf8.encode_rune(r)
    return insert_raw_array(b, pos, bytes[:])
}

@(private="file")
insert_raw_string :: proc(b: ^Buffer, pos: Buffer_Cursor, str: string) -> int {
    return insert_raw_array(b, pos, transmute([]byte)str)
}

buffer_len :: proc(b: ^Buffer) -> int {
    gap := b.gap_end - b.gap_start
    return len(b.data) - gap
}

@(private="file")
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

@(private="file")
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
