package main

import "core:fmt"
import "core:log"
import "core:prof/spall"

Debug :: struct {
    show_debug_info: bool,
    profiling:       bool,
    spall_buf:       spall.Buffer,
    spall_ctx:       spall.Context,
    rect:            Rect,
    texture:         ^Texture,
}

debug: Debug

debug_init :: proc() {
    width := f32(window_width/3)
    height := f32(window_height/3)
    debug.rect = {f32(window_width)-width, 0, width, height}
    debug.texture = texture_create(.TARGET, i32(width), i32(height))
}

debug_destroy :: proc() {
    texture_destroy(debug.texture)
}

debug_draw :: proc() {
    if !debug.show_debug_info do return
    set_target(debug.texture)
    set_background(16, 16, 16, 170)
    prepare_for_drawing()
    pane := active_pane
    lines := get_lines_array(pane)
    font_regular := fonts_map[.UI]
    font_bold := fonts_map[.UI_Bold]
    pen := [2]f32{
        10, 0,
    }
    piece_index: int

    for cursor, cursor_index in pane.cursors {
        pen = draw_text(font_bold, pen, fmt.tprintf("-- Cursor {} --\n", cursor_index))

        coords := cursor_offset_to_coords(pane, lines, cursor.pos)
        cursor_pos_str := fmt.tprintf(
            "Offset: {}\nCoords:  Col {} Row {}\n\n",
            cursor.pos, coords.column, coords.row,
        )

        pen = draw_text(font_regular, pen, cursor_pos_str)
        piece_index, _ = locate_piece(pane.buffer, cursor.pos)
    }

    pen = draw_text(font_bold, pen, "-- Buffer info --\n")
    buffer_info_str := fmt.tprintf(
        "Length: {}\nPieces: {}\nLine starts:\n{}\n\n",
        len(pane.contents.buf), len(pane.buffer.pieces), pane.line_starts,
    )
    pen = draw_text(font_regular, pen, buffer_info_str)

    pen = draw_text(font_bold, pen, "--Piece Information--\n")
    piece := pane.buffer.pieces[piece_index]
    piece_info := fmt.tprintf(
        "Index: {}\tSource: {}\nStart: {}\tLength: {}\n",
        piece_index, piece.source, piece.start, piece.length,
    )
    pen = draw_text(font_regular, pen, piece_info)

    set_target()
    draw_texture(debug.texture, nil, &debug.rect)
}

profiling_init :: proc() {
    log.debug("Initializing profiling")
	debug.spall_ctx = spall.context_create("profile.spall")
	buf := make([]u8, spall.BUFFER_DEFAULT_SIZE)
	debug.spall_buf = spall.buffer_create(buf)
    debug.profiling = true
}

profiling_destroy :: proc() {
    log.debug("Destroying profiling")
    buf := debug.spall_buf.data
    spall.buffer_destroy(&debug.spall_ctx, &debug.spall_buf)
    delete(buf)
    spall.context_destroy(&debug.spall_ctx)
    debug.profiling = false
}

profiling_start :: proc(name: string, loc := #caller_location) {
    if !debug.profiling do return
    spall._buffer_begin(&debug.spall_ctx, &debug.spall_buf, name, "", loc)
}

profiling_end :: proc() {
    if !debug.profiling do return
    spall._buffer_end(&debug.spall_ctx, &debug.spall_buf)
}
