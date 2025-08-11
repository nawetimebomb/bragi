package main

import "base:runtime"
import "core:encoding/uuid"
import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:thread"
import "core:time"
import "core:unicode/utf8"

UNDO_DEFAULT_TIMEOUT :: 300 * time.Millisecond

Buffer_Section_Kind :: enum u8 {
    none,
}

Cursor_Operation :: enum {
    DELETE, SWITCH, TOGGLE_GROUP,
}

Cursor_Translation :: enum {
    DOWN, LEFT, RIGHT, UP,
    BUFFER_END, BUFFER_START,
    LINE_END, LINE_START,
    WORD_END, WORD_START,
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

Buffer_Section :: struct {
    using range: Range,
    kind: Buffer_Section_Kind,
}

History_State :: struct {
    cursors_pos: []int,
    data:        string,
}

Buffer :: struct {
    allocator:           runtime.Allocator,
    id:                  uuid.Identifier,

    sections:            []Buffer_Section,
    cursors:             [dynamic]Cursor,
    interactive_mode:    bool, // when the user have control of the multiple cursors
    group_mode:          bool, // the user wants to control all cursors at the same time
    selection_mode:      bool, // when the user is doing selection with their keyboard

    // Save the cursor incursion to recreate lines faster
    cursor_incursion: struct {
        before:    int,
        after:     int,
        direction: enum { backward, forward },
    },

    indentation: struct {
        type: enum { space, tab },
        width: int,
    },

    data:                [dynamic]byte,
    tokens:              [dynamic]Token_Kind,
    dirty:               bool,
    lines:               [dynamic]int,
    str:                 string,

    enable_history:      bool,
    redo:                [dynamic]History_State,
    undo:                [dynamic]History_State,
    history_limit:       int,
    current_time:        time.Tick,
    last_edit_time:      time.Tick,
    undo_timeout:        time.Duration,

    status:              string,
    filepath:            string,
    major_mode:          Major_Mode,
    name:                string,
    readonly:            bool,
    modified:            bool,
    crlf:                bool,

    last_update_frame:   u64,
}

buffer_init :: proc(
    name: string,
    bytes: int,
    undo_timeout := UNDO_DEFAULT_TIMEOUT,
    allocator := context.allocator,
) -> Buffer {
    b := Buffer{
        allocator      = allocator,
        id             = uuid.generate_v7(),

        str            = "",
        dirty          = false,
        lines          = make([dynamic]int, 0, 16),

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
        id             = uuid.generate_v7(),
        dirty          = false,
        enable_history = true,
        lines          = make([dynamic]int, 0, 16),
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
    result.indentation.width = 4

    insert_whole_file(result, data)

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
    if b.last_update_frame == frame_counter { return }
    should_update_panes := false

    update_buffer_time(b)

    if len(b.cursors) == 0 {
        delete_all_cursors(b, make_cursor())
        should_update_panes = true
    }

    if b.interactive_mode {
        if len(b.cursors) == 1 {
            b.interactive_mode = false
            should_update_panes = true
        } else {
            should_update_panes = check_overlapping_cursors(b) || should_update_panes
        }
    }

    if b.dirty {
        b.dirty = false
        should_update_panes = true

        b.status = get_buffer_status(b)

        refresh_string_buffer(b)
        recalculate_lines(b)
        maybe_tokenize_buffer(b)
    }

    if should_update_panes {
        report_update_to_panes_using_buffer(b)
    }
}

buffer_destroy :: proc(b: ^Buffer) {
    clear_history(&b.undo)
    clear_history(&b.redo)
    delete(b.data)
    delete(b.cursors)
    delete(b.filepath)
    delete(b.lines)
    delete(b.name)
    delete(b.redo)
    delete(b.sections)
    delete(b.tokens)
    delete(b.undo)
}

update_buffer_time :: proc(b: ^Buffer) {
    b.last_update_frame = frame_counter

    if b.enable_history {
        b.current_time = time.tick_now()
        if b.undo_timeout <= 0 {
            b.undo_timeout = UNDO_DEFAULT_TIMEOUT
        }
    }
}

recalculate_lines :: proc(b: ^Buffer) {
    profiling_start("buffer.odin:recalculate_lines")
    start := 0

    if len(b.lines) > 1 {
        first_modified_offset := b.cursor_incursion.before

        if b.cursor_incursion.direction == .backward {
            first_modified_offset = b.cursor_incursion.after
        }

        modified_line := get_line_index(b.lines[:], first_modified_offset)
        modified_bol, _ := get_line_boundaries(b.lines[:], modified_line)
        start = modified_bol
        remove_range(&b.lines, modified_line, len(b.lines))
    }

    append(&b.lines, start)

    for index := start; index < len(b.str); index += 1 {
        if b.str[index] == '\n' {
            append(&b.lines, index + 1)
        }
    }

    // last line, adding padding for safety
    append(&b.lines, buffer_len(b) + 1)

    // TODO: Actually check by modes
    if bragi.settings.line_wrap_by_default {
        for &p in open_panes {
            if p.buffer.id == b.id {
                recalculate_wrapped_lines(&p)
            }
        }
    }

    profiling_end()
}

find_earlier_offset_in_cursors :: proc(b: ^Buffer) -> (result: int) {
    result = buffer_len(b)
    for cursor in b.cursors { result = min(result, min(cursor.pos, cursor.sel)) }
    return
}

maybe_tokenize_buffer :: proc(b: ^Buffer) {
    profiling_start("buffer.odin:maybe_tokenize_buffer")

    tokenize_proc: #type proc(^Buffer, int, int) -> []Buffer_Section

    delete(b.sections)

    if b.major_mode == .Fundamental {
        // We don't tokenize Fundamental mode
        delete(b.tokens)
        return
    }

    clear(&b.tokens)

    if len(b.tokens) < buffer_len(b) {
        resize(&b.tokens, buffer_len(b))
    }

    #partial switch b.major_mode {
        case .Bragi: log.error("not implemented")
        case .Odin:  tokenize_proc = tokenize_odin
    }

    b.sections = tokenize_proc(b, -1, -1)

    profiling_end()
}

get_indentation_tokens :: proc(b: ^Buffer, start, end: int) -> []Indent_Token {
    tokenize_indent_proc: #type proc(^Buffer, int, int) -> []Indent_Token

    if b.major_mode == .Fundamental {
        return {}
    }

    #partial switch b.major_mode {
        case .Odin: tokenize_indent_proc = tokenize_odin_indent
    }

    return tokenize_indent_proc(b, start, end)
}

is_between_line :: #force_inline proc(lines: []int, line, pos: int) -> bool {
    assert(line < len(lines))
    start, end := get_line_boundaries(lines, line)
    return pos >= start && pos <= end
}

is_last_line :: #force_inline proc(lines: []int, line: int) -> bool {
    assert(line < len(lines))
    return line == len(lines) - 1
}

get_line_index :: #force_inline proc(lines: []int, pos: int) -> (line: int) {
    for _, index in lines {
        if is_between_line(lines, index, pos) {
            line = index
            break
        }
    }

    return
}

get_line_boundaries :: #force_inline proc(lines: []int, line: int) -> (start, end: int) {
    assert(line < len(lines))
    next_line_index := min(line + 1, len(lines) - 1)
    start = lines[line]
    end = lines[next_line_index] - 1
    return
}

get_line_length :: #force_inline proc(lines: []int, line: int) -> (length: int) {
    assert(line < len(lines))
    start, end := get_line_boundaries(lines, line)
    return end - start
}

get_line_text :: #force_inline proc(b: ^Buffer, lines: []int, line: int) -> (result: string) {
    assert(line < len(lines))
    start, end := get_line_boundaries(lines, line)
    return b.str[start:end]
}

get_line_start_after_indent :: #force_inline proc(b: ^Buffer, lines: []int, line: int) -> (offset: int) {
    assert(line < len(b.lines))
    bol, eol := get_line_boundaries(lines, line)
    offset = bol

    for offset < eol && is_whitespace_temp(b.str[offset]) {
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
        delete(item.cursors_pos)
        delete(item.data)
    }
    clear(history)
}

undo_redo :: proc(b: ^Buffer, undo, redo: ^[dynamic]History_State) {
    if len(undo) > 0 {
        push_history_state(b, redo)
        item := pop(undo)

        clear(&b.cursors)
        for pos in item.cursors_pos { append(&b.cursors, make_cursor(pos)) }
        delete(item.cursors_pos)

        clear(&b.data)
        insert_raw_string(b, 0, item.data)
        delete(item.data)

        b.dirty = true
        b.modified = true
    }
}

push_history_state :: proc(b: ^Buffer, history: ^[dynamic]History_State) -> mem.Allocator_Error {
    item := History_State{
        cursors_pos = make([]int, len(b.cursors)),
        data        = strings.clone(string(b.data[:])),
    }

    for cursor, index in b.cursors { item.cursors_pos[index] = cursor.pos }

    append(history, item) or_return

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
        err := os.write_entire_file_or_err(b.filepath, transmute([]byte)b.str)

        if err != nil {
            log.errorf("Error saving buffer {0}", b.name)
            return
        }

        b.crlf = false
        b.modified = false
    } else {
        log.debugf("Nothing to save in {0}", b.name)
    }
}

refresh_string_buffer :: proc(b: ^Buffer) {
    profiling_start("buffer.odin:refresh_string_buffer")
    builder := strings.builder_make(context.temp_allocator)
    start := 0
    end := buffer_len(b)
    b.str = string(b.data[:])
    profiling_end()
}

get_byte_at :: #force_inline proc(b: ^Buffer, pos: int) -> byte {
    return b.data[pos]
}

delete_all_cursors :: proc(b: ^Buffer, new_cursor: Cursor = {}) {
    clear(&b.cursors)
    append(&b.cursors, new_cursor)
    b.selection_mode = false
    b.group_mode = false
    b.interactive_mode = false
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

get_coords :: #force_inline proc(b: ^Buffer, lines: []int, pos: int) -> (result: Coords) {
    result.line = get_line_index(lines, pos)
    bol, _ := get_line_boundaries(lines, result.line)
    result.column = pos - bol
    return
}

use_last_cursor :: #force_inline proc(b: ^Buffer) -> (cursor: ^Cursor) {
    return &b.cursors[len(b.cursors) - 1]
}

get_last_cursor_pos_as_coords :: #force_inline proc(b: ^Buffer, lines: []int) -> (pos: Coords) {
    return get_coords(b, lines, get_last_cursor_pos(b))
}

get_last_cursor_pos :: #force_inline proc(b: ^Buffer) -> (pos: int) {
    return b.cursors[len(b.cursors) - 1].pos
}

get_last_cursor_decomp :: #force_inline proc(b: ^Buffer) -> (pos, sel, col_offset: int) {
    c := b.cursors[len(b.cursors) - 1]
    return c.pos, c.sel, c.col_offset
}

has_selection :: #force_inline proc(b: ^Buffer) -> (result: bool) {
    pos, sel, _ := get_last_cursor_decomp(b)
    return b.selection_mode || pos != sel
}

check_overlapping_cursors :: proc(b: ^Buffer) -> (cursors_changed: bool) {
    for i in 0..<len(b.cursors) {
        for j in 1..<len(b.cursors) {
            if i == j { continue }
            // merge cursors that are actually on the same position,
            // when no selection is happening
            if !has_selection(b) {
                pos1 := b.cursors[i].pos
                pos2 := b.cursors[j].pos

                if pos1 == pos2 {
                    ordered_remove(&b.cursors, i)
                    cursors_changed = true
                }
            } else {
                hi1 := max(b.cursors[i].pos, b.cursors[i].sel)
                lo2 := min(b.cursors[j].pos, b.cursors[j].sel)
                hi2 := max(b.cursors[j].pos, b.cursors[j].sel)

                if hi1 >= lo2 && hi1 < hi2 {
                    merge_cursors(b, i, j)
                    cursors_changed = true
                }
            }
        }
    }

    return
}

merge_cursors :: #force_inline proc(b: ^Buffer, i, j: int) {
    hi_index := max(i, j)
    lo_index := min(i, j)
    merged_cursor := &b.cursors[lo_index]
    c1 := b.cursors[i]
    c2 := b.cursors[j]

    if c1.pos > c1.sel {
        // going to the right
        merged_cursor.pos = max(c1.pos, c2.pos)
        merged_cursor.sel = min(c1.sel, c2.sel)
    } else {
        // going to the left
        merged_cursor.pos = min(c1.pos, c2.pos)
        merged_cursor.sel = max(c1.sel, c2.sel)
    }

    ordered_remove(&b.cursors, hi_index)
}

get_strings_in_selections :: proc(b: ^Buffer) -> (result: string) {
    str_buffer := strings.builder_make(context.temp_allocator)

    for cursor in b.cursors {
        start := min(cursor.pos, cursor.sel)
        end := max(cursor.pos, cursor.sel)
        strings.write_string(&str_buffer, b.str[start:end])
    }

    return strings.to_string(str_buffer)
}

set_last_cursor_pos :: #force_inline proc(b: ^Buffer, pos: int) {
    b.cursors[len(b.cursors) - 1] = {
        pos = pos,
        sel = pos,
        col_offset = -1,
    }
}

get_offset_from_coords :: proc(lines: []int, coords: Coords) -> (pos: int) {
    bol, _ := get_line_boundaries(lines, coords.line)
    return bol + coords.column
}

dwim_last_cursor_col_offset :: proc(cursor: ^Cursor, new_offset: int) -> (offset: int) {
    if new_offset == - 1 {
        cursor.col_offset = -1
    } else {
        cursor.col_offset = max(cursor.col_offset, new_offset)
    }

    return cursor.col_offset
}

get_line_indent_level :: proc(b: ^Buffer, line: int) -> (level: int) {
    bol, eol := get_line_boundaries(b.lines[:], line)
    indent_tokens := get_indentation_tokens(b, bol, eol)
    s := get_line_text(b, b.lines[:], line)
    level = 0

    if b.indentation.type == .space {
        space_count: f32 = 0
        for c in s { if c == ' ' { space_count += 1 } else { break } }
        level = int(math.ceil(space_count / f32(b.indentation.width)))
    } else {
        for c in s { if c == '\t' { level += 1 } else { break } }
    }

    for t in indent_tokens {
        if t.action == .open  { level += 1 }
        if t.action == .close { level -= 1 }
    }

    if b.indentation.type == .space {
        level *= b.indentation.width
    }

    return
}

get_indent_char :: #force_inline proc(b: ^Buffer) -> (char: byte) {
    return b.indentation.type == .space ? ' ' : '\t'
}

update_future_cursor_offsets :: proc(b: ^Buffer, starting_cursor, offset: int) {
    for i in starting_cursor..<len(b.cursors) {
        cursor := &b.cursors[i]
        cursor.pos = clamp(cursor.pos + offset, 0, buffer_len(b))
        cursor.sel = cursor.pos
        cursor.col_offset = -1
    }
}

remove :: proc(b: ^Buffer, count: int) {
    check_buffer_history_state(b)

    // Make a cheap safety check early to see if the user actually wanted to
    // delete the whole buffer but they did it with multiple cursors
    total_of_deleted_chars := abs(count * len(b.cursors))

    if total_of_deleted_chars >= buffer_len(b) {
        remove_raw(b, 0, buffer_len(b))
        delete_all_cursors(b, make_cursor())
        return
    }

    before := buffer_len(b)
    after := 0
    direction: i8

    for &cursor, index in b.cursors {
        chars_to_delete := count

        // Because we don't block the user to select the whole buffer with multiple
        // cursors, we need to add some safety to the deletion process to make sure
        // we can't fall out of bounds.
        if cursor.pos == 0 && count < 0 {
            continue
        } else if count < 0 {
            chars_to_delete = max(count, -cursor.pos)
        } else {
            chars_to_delete = min(count, buffer_len(b))
        }

        if chars_to_delete == 0 {
            continue
        }

        before = min(cursor.pos, before)
        remove_raw(b, cursor.pos, chars_to_delete)

        if count < 0 {
            update_future_cursor_offsets(b, index, chars_to_delete)
            after = min(cursor.pos, after)
            direction = -1
        } else {
            // Since we're deleting forward from the position, we don't want to update
            // our current cursor, but update all future ones because we need to find
            // their new offsets on the buffer. We also make sure we update them by
            // substracting the amount of characters that have been deleted from the
            // current cursor.
            update_future_cursor_offsets(b, index + 1, chars_to_delete * -1)
            after = max(cursor.pos, after)
            direction = 1
        }
    }

    b.cursor_incursion.before = before
    b.cursor_incursion.after = after
    b.cursor_incursion.direction = direction == -1 ? .backward : .forward
}

insert_indent :: proc(b: ^Buffer) {
    before := buffer_len(b)
    after := 0
    direction: i8

    if !has_selection(b) && len(b.cursors) == 1 {
        // If there's only one cursor, and there's no selection happening, we handle
        // it separatedly because we don't need to update the lines to figure out what's
        // the best indentation.
        cursor := use_last_cursor(b)
        before = min(cursor.pos, before)
        line := get_line_index(b.lines[:], cursor.pos)
        previous_line := line - 1
        indent_level := get_line_indent_level(b, line - 1)
        bol, eol := get_line_boundaries(b.lines[:], line)
        s := get_line_text(b, b.lines[:], line)
        cut_count := 0

        for {
            if s[cut_count] == ' ' || s[cut_count] == '\t' {
                cut_count += 1
            } else {
                break
            }
        }

        if cut_count == indent_level {
            return
        }

        check_buffer_history_state(b)

        update_offset := indent_level - cut_count

        if update_offset > 0 {
            indent_temp := strings.builder_make(context.temp_allocator)

            for i in 0..<update_offset  {
                strings.write_byte(&indent_temp, get_indent_char(b))
            }

            insert_raw(b, bol, strings.to_string(indent_temp))
        } else {
            remove_raw(b, bol, abs(update_offset))
        }

        if cursor.pos < bol + indent_level {
            cursor.pos = bol + indent_level
        } else {
            cursor.pos += update_offset
        }

        cursor.sel = cursor.pos
        cursor.col_offset = -1

        direction = update_offset >= 0 ? 1 : -1
        after = max(cursor.pos, after)
    } else {
        // If there's more than one cursor or a selection is happening, we need to
        // keep track of the line changes to figure out the indentation, which makes
        // this a little bit more difficult to manage
        // TODO: Support region and multicursor
    }

    b.cursor_incursion.before = before
    b.cursor_incursion.after = after
    b.cursor_incursion.direction = direction == -1 ? .backward : .forward
}

// Newline will need to indent, depending on the buffer configuration
insert_newline :: proc(b: ^Buffer) {
    check_buffer_history_state(b)
    before := buffer_len(b)
    after := 0

    // Because we haven't update the lines at this point, we need to keep track of the
    // added offset per operation, so we can ensure we get the right line when trying to
    // add a newline and indenting with multiple cursors.
    accumulated_added_offset := 0

    for &cursor, index in b.cursors {
        before = min(cursor.pos, before)
        line := get_line_index(b.lines[:], cursor.pos - accumulated_added_offset)
        indent_level := get_line_indent_level(b, line)

        newline_temp := strings.builder_make(context.temp_allocator)
        strings.write_byte(&newline_temp, '\n')

        for i in 0..<indent_level {
            strings.write_byte(&newline_temp, get_indent_char(b))
        }

        result := strings.to_string(newline_temp)
        insert_raw(b, cursor.pos, result)
        update_future_cursor_offsets(b, index, len(result))
        accumulated_added_offset += len(result)

        after = max(cursor.pos, after)
    }

    b.cursor_incursion.before = before
    b.cursor_incursion.after = after
    b.cursor_incursion.direction = .forward
}

insert_char :: proc(b: ^Buffer, char: byte) {
    check_buffer_history_state(b)
    before := buffer_len(b)
    after := 0

    for &cursor, index in b.cursors {
        before = min(cursor.pos, before)
        insert_raw(b, cursor.pos, char)
        update_future_cursor_offsets(b, index, 1)
        after = max(cursor.pos, after)
    }

    b.cursor_incursion.before = before
    b.cursor_incursion.after = after
    b.cursor_incursion.direction = .forward
}

insert_string :: proc(b: ^Buffer, str: string) {
    check_buffer_history_state(b)
    before := buffer_len(b)
    after := 0

    for &cursor, index in b.cursors {
        before = min(cursor.pos, before)
        insert_raw(b, cursor.pos, str)
        update_future_cursor_offsets(b, index, len(str))
        after = max(cursor.pos, after)
    }

    b.cursor_incursion.before = before
    b.cursor_incursion.after = after
    b.cursor_incursion.direction = .forward
}

buffer_len :: proc(b: ^Buffer) -> int {
    return len(b.data)
}

@(private="file")
insert_whole_file :: proc(b: ^Buffer, data: []byte) {
    processed_data := make([dynamic]byte, 0, len(data), context.temp_allocator)

    for c in data {
        if c == '\r' {
            b.crlf = true
            continue
        }

        append(&processed_data, c)
    }

    insert_raw(b, 0, string(processed_data[:]))
    b.modified = b.crlf
    b.dirty = true
}

@(private="file")
remove_raw :: proc(b: ^Buffer, pos: int, count: int) {
    pos1 := pos + count
    lo := min(pos, pos1)
    hi := max(pos, pos1)
    remove_range(&b.data, lo, hi)
    b.dirty = true
    b.modified = true
}

@(private="file")
insert_raw :: proc{
    insert_raw_char,
    insert_raw_rune,
    insert_raw_string,
}

@(private="file")
insert_raw_char :: proc(b: ^Buffer, pos: int, char: byte) {
    assert(pos >= 0 && pos <= buffer_len(b))
    inject_at(&b.data, pos, char)
    b.dirty = true
    b.modified = true
}

@(private="file")
insert_raw_string :: proc(b: ^Buffer, pos: int, str: string) {
    assert(pos >= 0 && pos <= buffer_len(b))
    inject_at(&b.data, pos, str)
    b.dirty = true
    b.modified = true
}

@(private="file")
insert_raw_rune :: proc(b: ^Buffer, pos: int, r: rune) {
    bytes, width := utf8.encode_rune(r)
    insert_raw_string(b, pos, string(bytes[:width]))
}
