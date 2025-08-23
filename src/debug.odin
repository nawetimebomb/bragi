package main

import "core:fmt"
import "core:log"
import "core:prof/spall"
import "core:time"

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
    height := f32(window_height)
    debug.rect = {f32(window_width)-width, 0, width, height}
    debug.texture = texture_create(.TARGET, i32(width), i32(height))
}

debug_destroy :: proc() {
    texture_destroy(debug.texture)
}

debug_draw :: proc() {
    if !debug.show_debug_info do return
    set_target(debug.texture)
    set_color(.debug_background)
    prepare_for_drawing()
    pane := active_pane
    lines := get_lines_array(pane)
    font_regular := fonts_map[.UI_Small]
    font_bold := fonts_map[.UI_Bold]
    pen := Vector2{10, 0}
    piece_index: int

    set_colors(.debug_foreground, {font_regular.texture, font_bold.texture})

    pen = draw_text(font_bold, pen, "-- General information --\n")

    pen = draw_text(font_bold, pen, "Current Buffer\n")
    buffer_info_str := fmt.tprintf(
        "Name: {}\nLength: {}\nPieces: {}\nLines: {}\n",
        pane.buffer.name, len(pane.contents), len(pane.buffer.pieces),
        len(pane.line_starts),
    )
    pen = draw_text(font_regular, pen, buffer_info_str)

    pen = draw_text(font_bold, pen, "Current Pane\n")
    pane_info_str := fmt.tprintf(
        "Visible: Cols {} Rows {}\nOffset: X {} Y {}\n\n",
        pane.visible_columns, pane.visible_rows,
        pane.x_offset, pane.y_offset,
    )
    pen = draw_text(font_regular, pen, pane_info_str)

    for cursor, cursor_index in pane.cursors {
        pen = draw_text(font_bold, pen, fmt.tprintf("-- Cursor {} --\n", cursor_index + 1))
        current_byte := 0 if cursor.pos >= len(pane.contents) else pane.contents[cursor.pos]

        coords := cursor_offset_to_coords(pane, lines, cursor.pos)
        cursor_pos_str := fmt.tprintf(
            "Offset: {}\nByte: {}\nCoords:  Col {} Row {}\n\n",
            cursor.pos, current_byte, coords.column, coords.row,
        )

        pen = draw_text(font_regular, pen, cursor_pos_str)

        if cursor.pos < len(pane.buffer.tokens) {
            pen = draw_text(font_regular, pen, fmt.tprintf("Token: {}\n\n", pane.buffer.tokens[cursor.pos]))
        }

        piece_index, _ = locate_piece(pane.buffer, cursor.pos)
    }

    pen = draw_text(font_bold, pen, "--Piece Information--\n")
    piece := pane.buffer.pieces[piece_index]
    piece_info_str := fmt.tprintf(
        "Index: {}   Source: {}\nStart: {}   Length: {}\n\n",
        piece_index, piece.source, piece.start, piece.length,
    )
    pen = draw_text(font_regular, pen, piece_info_str)

    frametime := time.duration_milliseconds(frame_delta_time)
    rest_of_info_str := fmt.tprintf(
        "FPS:       {}\nFrametime: %.3fms\nMemory:    {}kb",
        int(1000 / frametime),
        frametime,
        tracking_allocator.current_memory_allocated / 1024,
    )
    pen = draw_text(font_regular, pen, rest_of_info_str)

    set_target()
    debug.rect.x = f32(window_width) - debug.rect.w
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
