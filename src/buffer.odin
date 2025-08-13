package main

import "base:runtime"

import "core:log"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:time"

UNDO_TIMEOUT :: 1 * time.Second

Buffer_Flag :: enum u8 {
    Dirty     = 0, // change in the buffer state, needs to redraw
    Modified  = 1, // contents change compared to previous version
    Read_Only = 2, // can't be changed
    CRLF      = 3, // was saved before as CRLF, it will be converted to LF
}

Cursor_Mode :: enum u8 {
    Interactive = 0, // multiple cursors, controlling one
    Group       = 1, // multiple cursors, controlling all
    Selection   = 2, // doing selection, play with multiple cursors
}

Source_Buffer :: enum {
    add_buffer,
    original_buffer,
}

Buffer :: struct {
    allocator:        runtime.Allocator,

    cursors:          [dynamic]Cursor,
    cursor_modes:     bit_set[Cursor_Mode; u8],
    original_buffer:  strings.Builder,
    add_buffer:       strings.Builder,
    pieces:           [dynamic]Piece,
    length_of_buffer: int,
    line_starts:      [dynamic]int,

    indentation: struct {
        type:  enum { Space, Tab },
        width: int,
    },

    history_enabled:  bool,
    redo, undo:       [dynamic]^History_State,

    name:             string,
    status:           string,
    filepath:         string,
    major_mode:       Major_Mode,
    flags:            bit_set[Buffer_Flag; u8],
    last_edit_time:   time.Tick,
}

Cursor :: struct {
    pos:         int,
    sel:         int,
    // NOTE(nawe) like Emacs, I want to align the cursor to the last
    // largest offset if possible, this is very helpful when
    // navigating up and down a buffer. If the current row is larger
    // than last_column, the cursor will be positioned at last_cursor,
    // if it is smaller, it will be positioned at the end of the
    // row. Some commands will reset this value to -1.
    last_column: int,
}

Piece :: struct {
    source:      Source_Buffer,
    start:       int,
    length:      int,
    line_starts: [dynamic]int,
}

History_State :: struct {
    cursors: []Cursor,
    pieces:  []Piece,
}

Major_Mode :: union {
    Major_Mode_Odin,
}

Major_Mode_Odin :: struct {}

// TODO(nawe) maybe this should create it's own allocator
buffer_create :: proc(filepath := "", allocator := context.allocator) -> ^Buffer {
    result := new(Buffer)

    if filepath == "" {
        log.debug("creating empty buffer")
        buffer_init(result, "", allocator)
    } else {
        log.debugf("creating buffer for '{}'", filepath)
        buffer_init(result, "", allocator)
    }

    append(&open_buffers, result)
    return result
}

buffer_init :: proc(b: ^Buffer, contents := "", allocator := context.allocator) {
    contents_length := len(contents)

    b.allocator = allocator
    b.original_buffer = strings.builder_make_len(contents_length)
    b.add_buffer = strings.builder_make()
    b.history_enabled = true
    b.length_of_buffer = contents_length
    b.flags += {.Dirty}

    original_piece := Piece{
        source = .original_buffer,
        start  = 0,
        length = contents_length,
    }

    if contents_length > 0 {
        strings.write_string(&b.original_buffer, contents)
        recalculate_line_starts(b, &original_piece)
    }

    append(&b.pieces, original_piece)
}

buffer_destroy :: proc(b: ^Buffer) {
    strings.builder_destroy(&b.original_buffer)
    strings.builder_destroy(&b.add_buffer)
    undo_clear(b, &b.undo)
    undo_clear(b, &b.redo)

    for piece in b.pieces {
        delete(piece.line_starts)
    }

    delete(b.cursors)
    delete(b.pieces)
    delete(b.line_starts)
    delete(b.undo)
    delete(b.redo)
    free(b)
}

buffer_update :: proc(b: ^Buffer, builder: ^strings.Builder) -> (changed: bool) {
    assert(builder != nil)

    if len(&b.cursors) == 0 {
        add_cursor(b)
        changed = true
    }

    if .Dirty in b.flags {
        changed = true
        b.flags -= {.Dirty}
        total_length := 0
        strings.builder_reset(builder)
        clear(&b.line_starts)
        append(&b.line_starts, 0)

        for piece in b.pieces {
            buffer := &b.original_buffer.buf
            total_length += piece.length

            if piece.source == .add_buffer {
                buffer = &b.add_buffer.buf
            }

            strings.write_string(builder, string(buffer[piece.start:piece.start + piece.length]))
            append(&b.line_starts, ..piece.line_starts[:])
        }

        b.length_of_buffer = total_length
    }

    return
}

undo_clear :: proc(b: ^Buffer, undo: ^[dynamic]^History_State) {
    for len(undo) > 0 {
        item := pop(undo)
        delete(item.cursors)
        delete(item.pieces)
        free(item, b.allocator)
    }
}

undo_state_push :: proc(b: ^Buffer, undo: ^[dynamic]^History_State) -> mem.Allocator_Error {
    item := (^History_State)(
        mem.alloc(size_of(History_State) + len(b.cursors) + len(b.pieces),
                  align_of(History_State), b.allocator) or_return,
    )

    item.cursors = slice.clone(b.cursors[:])
    item.pieces  = slice.clone(b.pieces[:])

    append(undo, item) or_return
    return nil
}

undo :: proc(b: ^Buffer, undo, redo: ^[dynamic]^History_State) -> bool {
    if len(undo) > 0 {
        undo_state_push(b, redo)
        item := pop(undo)
        delete(b.cursors)
        delete(b.pieces)
        b.cursors = slice.clone_to_dynamic(item.cursors)
        b.pieces  = slice.clone_to_dynamic(item.pieces)
        free(item, b.allocator)
        return true
    }

    return false
}

add_cursor :: proc(b: ^Buffer, pos := 0) {
    append(&b.cursors, Cursor{ pos, pos, -1 })
}

clone_cursor :: proc(b: ^Buffer, cursor_to_clone: Cursor) -> ^Cursor {
    append(&b.cursors, cursor_to_clone)
    return &b.cursors[len(b.cursors) - 1]
}

cursor_has_selection :: proc(cursor: Cursor) -> bool {
    return cursor.pos != cursor.sel
}

get_cursors_for_drawing :: proc(b: ^Buffer) -> []Visible_Cursor {
    visible_cursors := make([]Visible_Cursor, len(b.cursors), context.temp_allocator)

    for &vcursor, vcursor_index in visible_cursors {
        buffer_cursor := b.cursors[vcursor_index]
        vcursor.has_selection = cursor_has_selection(buffer_cursor)

        for line_start, line_start_index in b.line_starts {
            if line_start_index == len(b.line_starts) - 1 {
                vcursor.pos.y = i32(line_start_index)
                vcursor.pos.x = i32(buffer_cursor.pos - line_start)
            } else {
                line_end := b.line_starts[line_start_index + 1]

                if buffer_cursor.pos >= line_start && buffer_cursor.pos < line_end {
                    vcursor.pos.y = i32(line_start_index)
                    vcursor.pos.x = i32(buffer_cursor.pos - line_start)
                }
            }
        }
    }

    return visible_cursors
}

update_forward_cursors :: proc(b: ^Buffer, starting_cursor, offset: int) {
    for cursor_index in starting_cursor..<len(b.cursors) {
        cursor := &b.cursors[cursor_index]
        cursor.pos = clamp(cursor.pos + offset, 0, b.length_of_buffer)
        cursor.sel = cursor.pos
        cursor.last_column = -1
    }
}

// This is usually the entry point for inserting since it's the one handling the multi-cursor insert.
insert_at_points :: proc(b: ^Buffer, text: string) -> (total_length_of_inserted_characters: int) {
    for &cursor, cursor_index in b.cursors {
        offset := insert_at(b, cursor.pos, text)
        total_length_of_inserted_characters += offset
        cursor.pos += offset
        update_forward_cursors(b, cursor_index + 1, offset)
    }

    return
}

insert_newlines_and_indent :: proc(b: ^Buffer) -> (total_length_of_inserted_characters: int) {
    for &cursor, cursor_index in b.cursors {
        // TODO(nawe) add indentation
        offset := insert_at(b, cursor.pos, "\n")
        total_length_of_inserted_characters += offset
        cursor.pos += offset
        update_forward_cursors(b, cursor_index + 1, offset)
    }

    return
}

// The entry point for removing, with multi-cursor support.
// TODO(nawe) make sure we don't go below 0 when removing.
remove_at_points :: proc(b: ^Buffer, amount: int) -> (total_amount_of_removed_characters: int) {
    for &cursor, cursor_index in b.cursors {
        characters_to_remove := amount

        if cursor.pos == 0 && amount < 0 {
            continue
        } else if amount < 0 {
            characters_to_remove = max(amount, -cursor.pos)

            remove_at(b, cursor.pos, characters_to_remove)
            update_forward_cursors(b, cursor_index, characters_to_remove)
        } else {
            characters_to_remove = min(amount, b.length_of_buffer)

            remove_at(b, cursor.pos, characters_to_remove)
            update_forward_cursors(b, cursor_index + 1, characters_to_remove * -1)
        }

        total_amount_of_removed_characters += characters_to_remove
    }

    return
}

@(private="file")
insert_at :: proc(b: ^Buffer, pos: int, text: string) -> (length_of_text: int) {
    add_buffer_length := len(b.add_buffer.buf)
    length_of_text = len(text)
    piece_index, new_offset := locate_piece(b, pos)
    piece := &b.pieces[piece_index]
    end_of_piece := piece.start + piece.length
    b.flags += {.Dirty}

    strings.write_string(&b.add_buffer, text)

    // If the cursor is at the end of a piece, and that also points to the end
    // of the add buffer, we just need to grow the length of that piece. This is
    // the most common operation while entering text in sequence.
    if piece.source == .add_buffer && new_offset == end_of_piece && add_buffer_length == end_of_piece {
        piece.length += length_of_text
        recalculate_line_starts(b, piece)
        return
    }

    // We may need to split the piece into up to three pieces if the text was
    // added in the middle of an existing piece. We only care about the pieces
    // that have positive length to be added back.
    left := Piece{
        source = piece.source,
        start  = piece.start,
        length = new_offset - piece.start,
    }
    middle := Piece{
        source = .add_buffer,
        start  = add_buffer_length,
        length = length_of_text,
    }
    right := Piece{
        source = piece.source,
        start  = new_offset,
        length = piece.length - (new_offset - piece.start),
    }

    new_pieces := slice.filter([]Piece{left, middle, right}, proc(new_piece: Piece) -> bool {
        return new_piece.length > 0
    }, context.temp_allocator)

    if time.tick_diff(b.last_edit_time, time.tick_now()) > UNDO_TIMEOUT {
        undo_state_push(b, &b.undo)
    }

    for &new_piece in new_pieces {
        recalculate_line_starts(b, &new_piece)
    }

    delete(b.pieces[piece_index].line_starts)
    ordered_remove(&b.pieces, piece_index)
    inject_at(&b.pieces, piece_index, ..new_pieces)
    b.last_edit_time = time.tick_now()

    return
}

@(private="file")
remove_at :: proc(b: ^Buffer, pos: int, amount: int) {
    assert(pos >= 0)

    if amount == 0 {
        return
    }

    if amount < 0 {
        remove_at(b, pos + amount, -amount)
        return
    }

    // Remove may affect multiple pieces.
    first_piece_index, first_offset := locate_piece(b, pos)
    last_piece_index, last_offset := locate_piece(b, pos + amount)
    b.flags += {.Dirty}

    // Only one piece was affected, either at the beginning of the piece or at the end.
    if first_piece_index == last_piece_index {
        piece := &b.pieces[first_piece_index]

        if first_offset == piece.start {
            piece.start += amount
            piece.length -= amount
            recalculate_line_starts(b, piece)
            return
        } else if last_offset == piece.start + piece.length {
            piece.length -= amount
            recalculate_line_starts(b, piece)
            return
        }
    }

    // Multiple pieces were affected, we need to correct them.
    first_piece := b.pieces[first_piece_index]
    last_piece := b.pieces[last_piece_index]

    left := Piece{
        source = first_piece.source,
        start  = first_piece.start,
        length = first_offset - first_piece.start,
    }
    right := Piece{
        source = last_piece.source,
        start  = last_offset,
        length = last_piece.length - (last_offset - last_piece.start),
    }
    new_pieces := slice.filter([]Piece{left, right}, proc(new_piece: Piece) -> bool {
        return new_piece.length > 0
    }, context.temp_allocator)

    if time.tick_diff(b.last_edit_time, time.tick_now()) > UNDO_TIMEOUT {
        undo_state_push(b, &b.undo)
    }

    for &new_piece in new_pieces {
        recalculate_line_starts(b, &new_piece)
    }

    for temp_index in first_piece_index..<last_piece_index - first_piece_index + 1 do delete(b.pieces[temp_index].line_starts)
    remove_range(&b.pieces, first_piece_index, last_piece_index - first_piece_index + 1)
    inject_at(&b.pieces, first_piece_index, ..new_pieces)
    b.last_edit_time = time.tick_now()
}

@(private="file")
locate_piece :: proc(b: ^Buffer, pos: int) -> (piece_index, new_offset: int) {
    assert(pos >= 0)
    remaining := pos

    for piece, index in b.pieces {
        if remaining <= piece.length {
            return index, piece.start + remaining
        }
        remaining -= piece.length
    }

    unreachable()
}

@(private="file")
recalculate_line_starts :: proc(b: ^Buffer, piece: ^Piece) {
    str: string

    switch piece.source {
    case .original_buffer: str = strings.to_string(b.original_buffer)
    case .add_buffer:      str = strings.to_string(b.add_buffer)
    }

    clear(&piece.line_starts)

    for r, index in str[piece.start:piece.start + piece.length] {
        if r == '\n' do append(&piece.line_starts, index + 1)
    }
}
