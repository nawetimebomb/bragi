package main

// import "core:fmt"
// import "core:strings"

// Buffer :: struct {
//     name     : string,
//     filepath : string,
//     modified : bool,
//     readonly : bool,
//     lines    : [dynamic]Line,
//     cursor   : Cursor,
//     viewport : Vector2,
// }

// buffer_insert_at_point :: proc(text: cstring) {
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position
//     builder := strings.builder_make(context.temp_allocator)

//     strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
//     strings.write_string(&builder, string(text))
//     strings.write_string(&builder, buf.lines[new_pos.y][new_pos.x:])

//     delete(buf.lines[new_pos.y])
//     new_pos.x += 1
//     buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
//     buf.cursor.position = new_pos
//     buf.modified = true
// }

// // TODO: Currently this function is always adding 4 spaces, but technically
// // it should always look at the configuration of the language it's being
// // edit, and also, what are the block delimiters.
// buffer_newline :: proc() {
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position
//     og_line_index := buf.cursor.position.y
//     new_line_indent := get_string_indentation(buf.lines[og_line_index])
//     builder := strings.builder_make(context.temp_allocator)

//     current_line_content_before_break := buf.lines[og_line_index][:new_pos.x]
//     line_content_after_break := buf.lines[og_line_index][new_pos.x:]

//     buf.lines[og_line_index] = current_line_content_before_break

//     if is_code_block_open(og_line_index) {
//         new_line_indent += 4
//     }

//     for _ in 0..<new_line_indent { strings.write_rune(&builder, ' ') }
//     strings.write_string(&builder, line_content_after_break)
//     inject_at(&buf.lines, og_line_index + 1, strings.clone(strings.to_string(builder)))

//     new_pos.y += 1
//     new_pos.x = len(buf.lines[new_pos.y])

//     buf.cursor.position = new_pos
//     buf.modified = true
// }

// buffer_delete_word_backward :: proc() {
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position
//     line_indent := get_string_indentation(buf.lines[new_pos.y])
//     builder := create_string_builder()

//     if new_pos.x == 0 {
//         buffer_delete_char_backward()
//     } else {
//         new_pos.x = find_backward_word(buf.lines[new_pos.y], new_pos.x)

//         if new_pos.x <= line_indent {
//             new_pos.x = 0
//         }

//         strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
//         strings.write_string(&builder, buf.lines[new_pos.y][buf.cursor.position.x:])

//         delete(buf.lines[new_pos.y])
//         buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
//         buf.cursor.position = new_pos
//         buf.modified = true
//     }
// }

// buffer_delete_word_forward :: proc() {
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position
//     line_indent := get_string_indentation(buf.lines[new_pos.y])
//     builder := create_string_builder()

//     if new_pos.x == len(buf.lines[new_pos.y]) {
//         buffer_delete_char_forward()
//     } else {
//         point_to_cut := find_forward_word(buf.lines[new_pos.y], new_pos.x)

//         if new_pos.x < line_indent {
//             point_to_cut = line_indent
//         }

//         strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
//         strings.write_string(&builder, buf.lines[new_pos.y][point_to_cut:])

//         delete(buf.lines[new_pos.y])
//         buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
//         buf.cursor.position = new_pos
//         buf.modified = true
//     }
// }

// buffer_delete_char_backward :: proc() {
//     buffer := get_buffer_from_current_pane()
//     delete_at(buffer, buffer.cursor, -1)
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position
//     builder := create_string_builder()

//     new_pos.x -= 1

//     if new_pos.x < 0 {
//         new_pos.y -= 1

//         if new_pos.y < 0 {
//             new_pos.y = 0
//             new_pos.x = 0
//         } else {
//             new_pos.x = len(buf.lines[new_pos.y])

//             strings.write_string(&builder, buf.lines[new_pos.y][:])
//             strings.write_string(&builder, buf.lines[new_pos.y + 1][:])
//             delete(buf.lines[new_pos.y])
//             delete(buf.lines[new_pos.y + 1])
//             ordered_remove(&buf.lines, new_pos.y + 1)
//             buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
//         }
//     } else {
//         strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
//         strings.write_string(&builder, buf.lines[new_pos.y][new_pos.x + 1:])
//         delete(buf.lines[new_pos.y])
//         buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
//     }

//     buf.cursor.position = new_pos
//     buf.modified = true
// }

// buffer_delete_char_forward :: proc() {
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position
//     builder := create_string_builder()

//     if new_pos.x >= len(buf.lines[new_pos.y]) {
//         if new_pos.y + 1 < len(buf.lines) {
//             strings.write_string(&builder, buf.lines[new_pos.y][:])
//             strings.write_string(&builder, buf.lines[new_pos.y + 1][:])
//             delete(buf.lines[new_pos.y])
//             delete(buf.lines[new_pos.y + 1])
//             ordered_remove(&buf.lines, new_pos.y + 1)
//             buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
//         }
//     } else {
//         strings.write_string(&builder, buf.lines[new_pos.y][:new_pos.x])
//         strings.write_string(&builder, buf.lines[new_pos.y][new_pos.x + 1:])
//         delete(buf.lines[new_pos.y])
//         buf.lines[new_pos.y] = strings.clone(strings.to_string(builder))
//     }

//     buf.cursor.position = new_pos
//     buf.modified = true
// }

// buffer_backward_char :: proc() {
//     buffer := get_buffer_from_current_pane()
//     buffer.cursor = max(buffer.cursor - 1, 0)

//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position

//     if new_pos.x > 0 {
//         new_pos.x -= 1
//     } else {
//         if new_pos.y > 0 {
//             new_pos.y -= 1
//             new_pos.x = len(buf.lines[new_pos.y])
//         }
//     }

//     buf.cursor.position = new_pos
// }

// buffer_backward_paragraph :: proc() {
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position

//     for y := new_pos.y - 1; y > 0; y -= 1 {
//         if len(buf.lines[y]) == 0 {
//             new_pos.y = y
//             new_pos.x = 0
//             break
//         }
//     }

//     if new_pos.y == buf.cursor.position.y {
//         new_pos.y = 0
//         new_pos.x = 0
//     }

//     buf.cursor.position = new_pos
// }

// buffer_backward_word :: proc() {
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position
//     prev_word_offset := find_backward_word(buf.lines[new_pos.y], new_pos.x)
//     line_indent := get_string_indentation(buf.lines[new_pos.y])

//     if new_pos.x == 0 {
//         if new_pos.y > 0 {
//             new_pos.y -= 1
//             new_pos.x = len(buf.lines[new_pos.y])
//         }
//     } else {
//         new_pos.x = prev_word_offset

//         if new_pos.x < line_indent {
//             new_pos.x = 0
//         }
//     }

//     buf.cursor.position = new_pos
// }

// buffer_forward_char :: proc() {
//     buffer := get_buffer_from_current_pane()
//     buffer.cursor = min(buffer.cursor + 1, length_of_buffer(buffer))

//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position
//     last_line := len(buf.lines) - 1

//     if new_pos.x < len(buf.lines[new_pos.y]) {
//         new_pos.x += 1
//     } else {
//         if new_pos.y < last_line {
//             new_pos.x = 0
//             new_pos.y += 1
//         }
//     }

//     buf.cursor.position = new_pos
// }

// buffer_forward_paragraph :: proc() {
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position

//     for y := new_pos.y + 1; y < len(buf.lines); y += 1 {
//         if len(buf.lines[y]) == 0 {
//             new_pos.y = y
//             new_pos.x = 0
//             break
//         }
//     }

//     if new_pos.y == buf.cursor.position.y {
//         new_pos.y = len(buf.lines) - 1
//         new_pos.x = 0
//     }

//     buf.cursor.position = new_pos
// }

// buffer_forward_word :: proc() {
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position
//     next_word_offset := find_forward_word(buf.lines[new_pos.y], new_pos.x)
//     last_line := len(buf.lines) - 1
//     line_indent := get_string_indentation(buf.lines[new_pos.y])

//     if new_pos.x >= len(buf.lines[new_pos.y]) {
//         if new_pos.y < last_line {
//             new_pos.y += 1
//             new_pos.x = get_string_indentation(buf.lines[new_pos.y])
//         }
//     } else {
//         new_pos.x = next_word_offset

//         if new_pos.x < line_indent {
//             new_pos.x = line_indent
//         }
//     }

//     buf.cursor.position = new_pos
// }

// buffer_previous_line :: proc() {
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position

//     if new_pos.y == 0 {
//         new_pos.x = 0
//         buf.cursor.previous_x = 0
//     } else {
//         new_pos.y -= 1
//         line_len := len(buf.lines[new_pos.y])

//         if new_pos.x != 0 && new_pos.x > buf.cursor.previous_x {
//             buf.cursor.previous_x = new_pos.x
//         }

//         if new_pos.x <= line_len && buf.cursor.previous_x <= line_len {
//             new_pos.x = buf.cursor.previous_x
//         } else {
//             new_pos.x = line_len
//         }
//     }

//     buf.cursor.position = new_pos
// }

// buffer_next_line :: proc() {
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position
//     last_line := len(buf.lines) - 1

//     if new_pos.y < last_line {
//         new_pos.y += 1
//         line_len := len(buf.lines[new_pos.y])

//         if new_pos.x != 0 && new_pos.x > buf.cursor.position.x {
//             buf.cursor.previous_x = new_pos.x
//         }

//         if new_pos.x <= line_len && buf.cursor.previous_x <= line_len {
//             new_pos.x = buf.cursor.previous_x
//         } else {
//             new_pos.x = line_len
//         }
//     }

//     buf.cursor.position = new_pos
// }

// buffer_beginning_of_buffer :: proc() {
//     buf := bragi.cbuffer
//     buf.cursor.position = { 0, 0 }
// }

// buffer_beginning_of_line :: proc() {
//     buf := bragi.cbuffer
//     new_pos := buf.cursor.position

//     if new_pos.x == 0 {
//         new_pos.x = get_string_indentation(buf.lines[new_pos.y])
//     } else {
//         new_pos.x = 0
//     }

//     buf.cursor.position = new_pos
// }

// buffer_end_of_buffer :: proc() {
//     buf := bragi.cbuffer
//     buf.cursor.position = { 0, len(buf.lines) - 1 }
// }

// buffer_end_of_line :: proc() {
//     buf := bragi.cbuffer
//     buf.cursor.position.x = len(buf.lines[buf.cursor.position.y])
// }

// buffer_page_size :: proc() -> Vector2 {
//     // NOTE: Because we have some UI content showing all the time in the editor,
//     // we have to limit the page size to the space that's actually seen,
//     // and make sure we scroll earlier.
//     EDITOR_UI_VIEWPORT_OFFSET :: 2

//     window_size := bragi.ctx.window_size
//     std_char_size := get_standard_character_size()
//     horizontal_page_size := (window_size.x / std_char_size.x) - EDITOR_UI_VIEWPORT_OFFSET
//     vertical_page_size := (window_size.y / std_char_size.y) - EDITOR_UI_VIEWPORT_OFFSET

//     return Vector2{ horizontal_page_size, vertical_page_size }
// }

// // TODO: Maybe improve this so it scrolls the camera instead of the cursor, and
// // then align the cursor if it ended up out of the screen
// buffer_scroll :: proc(offset: int) {
//     buf := bragi.cbuffer
//     last_line := len(buf.lines) - 1
//     page_size := buffer_page_size()
//     new_pos := buf.cursor.position

//     new_pos.y += offset

//     if new_pos.y > last_line {
//         new_pos.y = last_line
//         new_pos.x = 0
//     } else if new_pos.y < 0 {
//         new_pos.y = 0
//         new_pos.x = 0
//     } else {
//         new_pos.x = len(buf.lines[new_pos.y])
//     }

//     buf.cursor.position = new_pos
// }

// buffer_correct_viewport :: proc() {
//     pos := bragi.cbuffer.cursor.position
//     page_size := buffer_page_size()
//     new_viewport := bragi.cbuffer.viewport

//     if pos.x > new_viewport.x + page_size.x {
//         new_viewport.x = pos.x - page_size.x
//     } else if pos.x < new_viewport.x {
//         new_viewport.x = pos.x
//     }

//     if pos.y > new_viewport.y + page_size.y {
//         new_viewport.y = pos.y - page_size.y
//     } else if pos.y < new_viewport.y {
//         new_viewport.y = pos.y
//     }

//     bragi.cbuffer.viewport = new_viewport
// }
