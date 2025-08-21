package main

import "base:runtime"

import "core:encoding/uuid"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

UNDO_TIMEOUT :: 500 * time.Millisecond

Buffer_Flags :: bit_set[Buffer_Flag; u8]

Buffer_Flag :: enum u8 {
    Dirty     = 0, // change in the buffer state, needs to redraw
    Modified  = 1, // contents change compared to previous version
    Read_Only = 2, // can't be changed
    CRLF      = 3, // was saved before as CRLF, it will be converted to LF
    Scratch   = 4, // created by Bragi as scratchpad. If saved as file, this flag will be removed.
}

Source_Buffer :: enum {
    Add,
    Original,
}

Buffer :: struct {
    allocator:        runtime.Allocator,
    uuid:             uuid.Identifier,

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
    text_content:     strings.Builder,
    length_of_buffer: int,

    indent: struct {
        char:  Tab_Character,
        width: int,
    },

    history_enabled:  bool,
    redo, undo:       [dynamic]^History_State,

    name:             string,
    filepath:         string,
    major_mode:       Major_Mode,
    flags:            Buffer_Flags,
    last_edit_time:   time.Tick,
}

Piece :: struct {
    source:      Source_Buffer,
    start:       int,
    length:      int,
}

History_State :: struct {
    cursors: []Cursor,
    pieces:  []Piece,
}

Major_Mode :: union #no_nil {
    Major_Mode_Bragi,
    Major_Mode_Odin,
}

Major_Mode_Bragi :: struct {}

Major_Mode_Odin :: struct {}

buffer_get_or_create_empty :: proc(name: string = "*scratchpad*") -> ^Buffer {
    for buffer in open_buffers {
        if buffer.name == name {
            log.debugf("using existing buffer with name '{}'", name)
            return buffer
        }
    }

    log.debugf("creating new buffer with name '{}'", name)
    result := new(Buffer)
    buffer_init(result, {})
    result.name = strings.clone(name)
    if name == "*scratchpad*" do flag_buffer(result, {.Scratch})
    append(&open_buffers, result)
    return result
}

buffer_get_or_create_from_file :: proc(fullpath: string, contents: []byte) -> ^Buffer {
    for buffer in open_buffers {
        if buffer.filepath == fullpath {
            log.debugf("found buffer for '{}'", fullpath)
            return buffer
        }
    }

    log.debugf("creating buffer for file '{}'", fullpath)
    result := new(Buffer)
    buffer_init(result, contents)
    result.filepath = strings.clone(fullpath)
    result.name = strings.clone(filepath.base(result.filepath))
    append(&open_buffers, result)
    return result
}

buffer_init :: proc(buffer: ^Buffer, contents: []byte, allocator := context.allocator) {
    buffer.allocator = allocator
    buffer.uuid = uuid.generate_v6()
    buffer.original_source = strings.builder_make_len_cap(0, len(contents))
    buffer.add_source = strings.builder_make()
    buffer.history_enabled = true
    flag_buffer(buffer, {.Dirty})

    for b in contents {
        if b == '\r' {
            // remove carriage returns
            flag_buffer(buffer, {.CRLF, .Modified})
            continue
        }

        strings.write_byte(&buffer.original_source, b)
    }

    contents_length := len(buffer.original_source.buf)
    buffer.length_of_buffer = contents_length

    original_piece := Piece{
        source = .Original,
        start  = 0,
        length = contents_length,
    }
    append(&buffer.pieces, original_piece)
}

buffer_index :: proc(buffer: ^Buffer) -> int {
    for other, index in open_buffers {
        if buffer.uuid == other.uuid do return index
    }

    unreachable()
}

buffer_save :: proc(buffer: ^Buffer) {
    if .Modified not_in buffer.flags {
        log.debug("no changes need to be saved")
        return
    }

    // ensure file ends in newline to be POSIX compliant
    temp_builder := strings.builder_make(context.temp_allocator)
    buffer_len := len(buffer.text_content.buf)
    buf := buffer.text_content.buf
    if buf[buffer_len - 1] != '\n' do strings.write_byte(&temp_builder, '\n')

    if len(temp_builder.buf) > 0 {
        temp_str := strings.to_string(temp_builder)
        insert_at(buffer, buffer_len, temp_str)
        strings.write_string(&buffer.text_content, temp_str)
    }

    unflag_buffer(buffer, {.CRLF, .Modified})

    if !os.exists(buffer.filepath) {
        // since the file doesn't exists, we might need to also make the directory
        expected_dir := filepath.dir(buffer.filepath, context.temp_allocator)
        if !os.exists(expected_dir) {
            error := os.make_directory(expected_dir)

            if error != nil {
                log.fatalf("could not create directory '{}' for buffer '{}' due to {}", expected_dir, buffer.name, error)
                return
            }
        }

        if !os.is_dir(expected_dir) {
            log.fatalf("the path to directory in buffer '{}' is not an actual directory '{}'", buffer.name, buffer.filepath)
            return
        }
    }

    error := os.write_entire_file_or_err(buffer.filepath, buffer.text_content.buf[:])
    if error != nil {
        log.fatalf("could not save buffer '{}' at {} due to {}", buffer.name, buffer.filepath, error)
        return
    }

    log.debugf("wrote {}", buffer.filepath)
}

buffer_destroy :: proc(buffer: ^Buffer) {
    strings.builder_destroy(&buffer.original_source)
    strings.builder_destroy(&buffer.add_source)
    strings.builder_destroy(&buffer.text_content)
    undo_clear(buffer, &buffer.undo)
    undo_clear(buffer, &buffer.redo)
    delete(buffer.cursors)
    delete(buffer.pieces)
    delete(buffer.undo)
    delete(buffer.redo)
    delete(buffer.name)
    if buffer.filepath != "" do delete(buffer.filepath)
    free(buffer)
}

update_opened_buffers :: proc() {
    profiling_start("updating opened buffers")
    for buffer in open_buffers {
        is_active_in_panes := false

        for pane in open_panes {
            if pane.buffer.uuid == buffer.uuid {
                is_active_in_panes = true
                break
            }
        }

        if !is_active_in_panes do continue

        if .Dirty in buffer.flags {
            unflag_buffer(buffer, {.Dirty})
            total_length := 0
            strings.builder_reset(&buffer.text_content)
            lines_array := make([dynamic]int, context.temp_allocator)

            for piece in buffer.pieces {
                start, end := piece.start, piece.start + piece.length

                switch piece.source {
                case .Add:      strings.write_string(&buffer.text_content, strings.to_string(buffer.add_source)[start:end])
                case .Original: strings.write_string(&buffer.text_content, strings.to_string(buffer.original_source)[start:end])
                }

                total_length += piece.length
            }

            buffer.length_of_buffer = total_length
            append(&lines_array, 0)
            for r, index in strings.to_string(buffer.text_content) {
                if r == '\n' do append(&lines_array, index + 1)
            }
            append(&lines_array, total_length + 1)

            for pane in open_panes {
                if pane.buffer != buffer do continue
                delete(pane.line_starts)
                pane.contents = strings.to_string(buffer.text_content)
                pane.line_starts = slice.clone_to_dynamic(lines_array[:])
                if .Line_Wrappings in pane.modes do recalculate_line_wrappings(pane)
                flag_pane(pane, {.Need_Full_Repaint})
            }
        }
    }
    profiling_end()
}

undo_clear :: proc(buffer: ^Buffer, undo: ^[dynamic]^History_State) {
    for len(undo) > 0 {
        item := pop(undo)
        delete(item.cursors)
        delete(item.pieces)
        free(item, buffer.allocator)
    }
}

undo_state_push :: proc(buffer: ^Buffer, undo: ^[dynamic]^History_State) -> mem.Allocator_Error {
    log.debug("pushing new undo state")
    item := (^History_State)(
        // safe to use b.cursors here because we should always have a copy at hand when doing this
        mem.alloc(size_of(History_State) + len(buffer.cursors) + len(buffer.pieces),
                  align_of(History_State), buffer.allocator) or_return,
    )

    item.cursors = slice.clone(buffer.cursors[:])
    item.pieces  = slice.clone(buffer.pieces[:])

    append(undo, item) or_return
    return nil
}

undo :: proc(buffer: ^Buffer, undo, redo: ^[dynamic]^History_State) -> (result: bool, cursors: []Cursor, pieces: []Piece) {
    if len(undo) > 0 {
        undo_state_push(buffer, redo)
        item := pop(undo)
        cursors = slice.clone(item.cursors, context.temp_allocator)
        pieces = slice.clone(item.pieces, context.temp_allocator)
        delete(item.cursors)
        delete(item.pieces)
        free(item, buffer.allocator)
        flag_buffer(buffer, {.Dirty, .Modified})
        return true, cursors, pieces
    }

    return false, {}, {}
}

copy_cursors :: proc(pane: ^Pane, buffer: ^Buffer) {
    delete(buffer.cursors)
    buffer.cursors = slice.clone(pane.cursors[:])
}

flag_buffer :: #force_inline proc(buffer: ^Buffer, flags: Buffer_Flags) {
    buffer.flags += flags
}

unflag_buffer :: #force_inline proc(buffer: ^Buffer, flags: Buffer_Flags) {
    buffer.flags -= flags
}

is_modified :: #force_inline proc(buffer: ^Buffer) -> bool {
    return .Modified in buffer.flags
}

is_crlf :: #force_inline proc(buffer: ^Buffer) -> bool {
    return .CRLF in buffer.flags
}

is_continuation_byte :: proc(b: byte) -> bool {
	return b >= 0x80 && b < 0xc0
}

get_major_mode_name :: proc(buffer: ^Buffer) -> string {
    switch v in buffer.major_mode {
    case Major_Mode_Bragi: return "Bragi"
    case Major_Mode_Odin:  return "Odin"
    }

    unreachable()
}

insert_at :: proc(buffer: ^Buffer, offset: int, text: string) -> (length_of_text: int) {
    add_source_length := len(buffer.add_source.buf)
    length_of_text = len(text)
    piece_index, new_offset := locate_piece(buffer, offset)
    piece := &buffer.pieces[piece_index]
    end_of_piece := piece.start + piece.length
    flag_buffer(buffer, {.Dirty, .Modified})

    strings.write_string(&buffer.add_source, text)

    if time.tick_diff(buffer.last_edit_time, time.tick_now()) > UNDO_TIMEOUT do undo_state_push(buffer, &buffer.undo)
    buffer.last_edit_time = time.tick_now()

    // If the cursor is at the end of a piece, and that also points to the end
    // of the add buffer, we just need to grow the length of that piece. This is
    // the most common operation while entering text in sequence.
    if piece.source == .Add && new_offset == end_of_piece && add_source_length == end_of_piece {
        piece.length += length_of_text
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
        source = .Add,
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
    ordered_remove(&buffer.pieces, piece_index)
    inject_at(&buffer.pieces, piece_index, ..new_pieces)

    return
}

remove_at :: proc(buffer: ^Buffer, offset: int, amount: int) {
    assert(offset >= 0)
    if amount == 0 do return

    if amount < 0 {
        remove_at(buffer, offset + amount, -amount)
        return
    }

    if time.tick_diff(buffer.last_edit_time, time.tick_now()) > UNDO_TIMEOUT do undo_state_push(buffer, &buffer.undo)
    buffer.last_edit_time = time.tick_now()

    // Remove may affect multiple pieces.
    first_piece_index, first_offset := locate_piece(buffer, offset)
    last_piece_index, last_offset := locate_piece(buffer, offset + amount)
    flag_buffer(buffer, {.Dirty, .Modified})

    // Only one piece was affected, either at the beginning of the piece or at the end.
    if first_piece_index == last_piece_index {
        piece := &buffer.pieces[first_piece_index]

        if first_offset == piece.start {
            piece.start += amount
            piece.length -= amount
            return
        } else if last_offset == piece.start + piece.length {
            piece.length -= amount
            return
        }
    }

    // Multiple pieces were affected, we need to correct them.
    first_piece := buffer.pieces[first_piece_index]
    last_piece := buffer.pieces[last_piece_index]

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

    remove_range(&buffer.pieces, first_piece_index, last_piece_index + 1)
    inject_at(&buffer.pieces, first_piece_index, ..new_pieces)
}

locate_piece :: proc(buffer: ^Buffer, offset: int) -> (piece_index, new_offset: int) {
    assert(offset >= 0)
    remaining := offset

    for piece, index in buffer.pieces {
        if remaining <= piece.length {
            return index, piece.start + remaining
        }
        remaining -= piece.length
    }

    unreachable()
}
