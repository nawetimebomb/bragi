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

Source_Buffer :: enum {
    add,
    original,
}

Buffer :: struct {
    allocator:        runtime.Allocator,

    // NOTE(nawe) this cursor array should ALWAYS be a view to the
    // pane cursors array, hence there's no allocation happening. This
    // is important because we're not freeing this, since is always
    // freed from the pane. This retains a view so when an edit
    // happens we can save it in the undo/redo array and then, when
    // undoing, recover that state.
    cursors:          []Cursor,
    original_source:  strings.Builder,
    add_source:       strings.Builder,
    pieces:           [dynamic]Piece,
    length_of_buffer: int,

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
    b.original_source = strings.builder_make_len(contents_length)
    b.add_source = strings.builder_make()
    b.history_enabled = true
    b.length_of_buffer = contents_length
    b.flags += {.Dirty}

    strings.write_string(&b.original_source, contents)
    original_piece := Piece{
        source = .original,
        start  = 0,
        length = contents_length,
    }
    recalculate_piece_line_starts(b, &original_piece)
    append(&b.pieces, original_piece)
}

buffer_destroy :: proc(b: ^Buffer) {
    strings.builder_destroy(&b.original_source)
    strings.builder_destroy(&b.add_source)
    undo_clear(b, &b.undo)
    undo_clear(b, &b.redo)

    for piece in b.pieces {
        delete(piece.line_starts)
    }

    delete(b.pieces)
    delete(b.undo)
    delete(b.redo)
    free(b)
}

buffer_update :: proc(buffer: ^Buffer, pane: ^Pane, force_update := false) -> (changed: bool) {
    profiling_start("buffer_update")
    if .Dirty in buffer.flags || force_update {
        buffer.flags -= {.Dirty}
        total_length := 0
        strings.builder_reset(&pane.contents)
        clear(&pane.line_starts)
        append(&pane.line_starts, 0)

        for piece in buffer.pieces {
            data := &buffer.original_source.buf
            total_length += piece.length

            if piece.source == .add {
                data = &buffer.add_source.buf
            }

            append(&pane.line_starts, ..piece.line_starts[:])
            strings.write_string(&pane.contents, string(data[piece.start:piece.start + piece.length]))
        }

        // adding an extra line to make line searching easier
        append(&pane.line_starts, total_length + 1)
        buffer.length_of_buffer = total_length
    }
    profiling_end()

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
        // safe to use b.cursors here because we should always have a copy at hand when doing this
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
        b.cursors = slice.clone(item.cursors)
        b.pieces  = slice.clone_to_dynamic(item.pieces)
        free(item, b.allocator)
        return true
    }

    return false
}

cursor_has_selection :: proc(cursor: Cursor) -> bool {
    return cursor.pos != cursor.sel
}

update_forward_cursors :: proc(b: ^Buffer, cursors: ^[dynamic]Cursor, starting_cursor, offset: int) {
    for cursor_index in starting_cursor..<len(cursors) {
        cursor := &cursors[cursor_index]
        cursor.pos = clamp(cursor.pos + offset, 0, b.length_of_buffer)
        cursor.sel = cursor.pos
        cursor.last_column = -1
    }
}

// This is usually the entry point for inserting since it's the one handling the multi-cursor insert.
insert_at_points :: proc(b: ^Buffer, cursors: ^[dynamic]Cursor, text: string) -> (total_length_of_inserted_characters: int) {
    profiling_start("taking input")
    b.cursors = cursors[:]
    for &cursor, cursor_index in cursors {
        offset := insert_at(b, cursor.pos, text)
        total_length_of_inserted_characters += offset
        cursor.pos += offset
        update_forward_cursors(b, cursors, cursor_index + 1, offset)
    }
    profiling_end()

    return
}

insert_newlines_and_indent :: proc(b: ^Buffer, cursors: ^[dynamic]Cursor) -> (total_length_of_inserted_characters: int) {
    b.cursors = cursors[:]
    for &cursor, cursor_index in cursors {
        // TODO(nawe) add indentation
        offset := insert_at(b, cursor.pos, "\n")
        total_length_of_inserted_characters += offset
        cursor.pos += offset
        update_forward_cursors(b, cursors, cursor_index + 1, offset)
    }

    return
}

// The entry point for removing, with multi-cursor support.
// TODO(nawe) make sure we don't go below 0 when removing.
remove_at_points :: proc(b: ^Buffer, cursors: ^[dynamic]Cursor, amount: int) -> (total_amount_of_removed_characters: int) {
    b.cursors = cursors[:]
    for &cursor, cursor_index in cursors {
        characters_to_remove := amount

        if cursor.pos == 0 && amount < 0 {
            continue
        } else if amount < 0 {
            characters_to_remove = max(amount, -cursor.pos)

            remove_at(b, cursor.pos, characters_to_remove)
            update_forward_cursors(b, cursors, cursor_index, characters_to_remove)
        } else {
            characters_to_remove = min(amount, b.length_of_buffer)

            remove_at(b, cursor.pos, characters_to_remove)
            update_forward_cursors(b, cursors, cursor_index + 1, characters_to_remove * -1)
        }

        total_amount_of_removed_characters += abs(characters_to_remove)
    }

    return
}

@(private="file")
insert_at :: proc(b: ^Buffer, pos: int, text: string) -> (length_of_text: int) {
    add_source_length := len(b.add_source.buf)
    length_of_text = len(text)
    piece_index, new_offset := locate_piece(b, pos)
    piece := &b.pieces[piece_index]
    end_of_piece := piece.start + piece.length
    b.flags += {.Dirty}

    strings.write_string(&b.add_source, text)

    // If the cursor is at the end of a piece, and that also points to the end
    // of the add buffer, we just need to grow the length of that piece. This is
    // the most common operation while entering text in sequence.
    if piece.source == .add && new_offset == end_of_piece && add_source_length == end_of_piece {
        piece.length += length_of_text
        recalculate_piece_line_starts(b, piece)
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
        source = .add,
        start  = add_source_length,
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

    if time.tick_diff(b.last_edit_time, time.tick_now()) > UNDO_TIMEOUT do undo_state_push(b, &b.undo)

    for &new_piece in new_pieces do recalculate_piece_line_starts(b, &new_piece)

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
            recalculate_piece_line_starts(b, piece)
            return
        } else if last_offset == piece.start + piece.length {
            piece.length -= amount
            recalculate_piece_line_starts(b, piece)
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

    if time.tick_diff(b.last_edit_time, time.tick_now()) > UNDO_TIMEOUT do undo_state_push(b, &b.undo)
    for &new_piece in new_pieces do recalculate_piece_line_starts(b, &new_piece)

    for delete_piece_index in first_piece_index..<last_piece_index - first_piece_index + 1 {
        delete(b.pieces[delete_piece_index].line_starts)
    }

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
recalculate_piece_line_starts :: proc(b: ^Buffer, piece: ^Piece) {
    profiling_start("recalculating piece line starts")
    clear(&piece.line_starts)
    text: string

    switch piece.source {
    case .original: text = strings.to_string(b.original_source)
    case .add:      text = strings.to_string(b.add_source)
    }

    for r, index in text[piece.start:piece.start + piece.length] {
        if r == '\n' do append(&piece.line_starts, index + 1)
    }
    profiling_end()
}
