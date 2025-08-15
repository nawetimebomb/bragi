package main

import     "core:fmt"
import     "core:log"
import     "core:slice"
import     "core:strings"

import sdl "vendor:sdl3"

Rect    :: sdl.FRect
Surface :: sdl.Surface
Texture :: sdl.Texture
Vector2 :: distinct [2]i32

Coords :: struct {
    row: int,
    column: int,
}

texture_create :: #force_inline proc(access: sdl.TextureAccess, w, h: i32) -> ^Texture {
    return sdl.CreateTexture(renderer, .RGBA32, access, w, h)
}

texture_destroy :: #force_inline proc(texture: ^Texture) {
    sdl.DestroyTexture(texture)
}

make_rect :: #force_inline proc(x, y, w, h: i32) -> Rect {
    return Rect{f32(x), f32(y), f32(w), f32(h)}
}

prepare_for_drawing :: #force_inline proc() {
    sdl.RenderClear(renderer)
}

draw_frame :: #force_inline proc() {
    sdl.RenderPresent(renderer)
}

draw_texture :: #force_inline proc(texture: ^Texture, src, dest: ^Rect, loc := #caller_location) {
    if !sdl.RenderTexture(renderer, texture, src, dest) {
        log.errorf("failed to render texture at '{}'", loc)
    }
}

set_background :: #force_inline proc(r, g, b: u8, a: u8 = 255) {
    sdl.SetRenderDrawColor(renderer, r, g, b, a)
}

set_foreground :: #force_inline proc(texture: ^Texture, r, g, b: u8) {
    sdl.SetTextureColorMod(texture, r, g, b)
}

set_target :: #force_inline proc(target: ^Texture = nil) {
    sdl.SetRenderTarget(renderer, target)
}

draw_code :: proc(font: ^Font, pen: Vector2, code_lines: []Code_Line) { //, selections: []Range) {

    for code, y_offset in code_lines {
        sx := pen.x
        sy := pen.y + (i32(y_offset) * get_line_height(font))

        for r in code.line {
            glyph := find_or_create_glyph(font, r)
            src := make_rect(glyph.x, glyph.y, glyph.w, glyph.h)
            dest := make_rect(sx, sy, glyph.w, glyph.h)
            set_foreground(font.texture, 160, 133, 99)
            draw_texture(font.texture, &src, &dest)
            sx += glyph.xadvance
        }
    }
}

draw_cursor :: proc(font: ^Font, pen: Vector2, rune_behind: rune, visible: bool, active: bool) {
    cursor_width := font.em_width if settings.cursor_is_a_block else i32(settings.cursor_width)
    cursor_height := font.character_height

    set_background(205, 149, 12)

    if active {
        if visible {
            draw_rect(pen.x, pen.y, cursor_width, cursor_height, true)

            if settings.cursor_is_a_block && rune_behind != ' ' && rune_behind != '\n' {
                glyph := find_or_create_glyph(font, rune_behind)
                src := make_rect(glyph.x, glyph.y, glyph.w, glyph.h)
                dest := make_rect(pen.x, pen.y, glyph.w, glyph.h)
                set_foreground(font.texture, 0, 0, 0)
                draw_texture(font.texture, &src, &dest)
            }
        }
    } else {
        draw_rect(pen.x, pen.y, cursor_width, cursor_height, false)
    }
}

draw_gutter :: proc(pane: ^Pane) -> (gutter_size: i32) {
    MINIMUM_GUTTER_PADDING :: 2
    LINE_NUMBER_JUSTIFY :: MINIMUM_GUTTER_PADDING/2
    pane_height := i32(pane.rect.h)
    font := fonts_map[.UI_Small]
    regular_character_height := get_line_height(fonts_map[.Editor])
    line_number_character_height := get_line_height(font)
    y_offset_for_centering := (regular_character_height - line_number_character_height) - 3

    if settings.show_line_numbers {
        buffer_lines := pane.line_starts[:]

        // NOTE(nawe) used to figure out how much space we need to
        // draw the gutter.
        size_test_str := fmt.tprintf("{}", len(buffer_lines))
        gutter_size = prepare_text(font, size_test_str) + MINIMUM_GUTTER_PADDING * font.em_width

        set_background(0, 0, 0)
        draw_rect(0, 0, gutter_size, pane_height, true)

        first_visible_row := pane.y_offset
        last_visible_row := pane.y_offset + pane.visible_rows
        last_line := len(buffer_lines) - 1
        pen := Vector2{}

        current_rows := make([dynamic]int, context.temp_allocator)
        for cursor in pane.cursors do append(&current_rows, get_line_index(cursor.pos, buffer_lines))

        for line_number in first_visible_row..<last_visible_row {
            if line_number >= last_line do break

            if slice.contains(current_rows[:], line_number) {
                set_background(19, 19, 19)
                draw_rect(0, pen.y, gutter_size, regular_character_height)
                set_foreground(font.texture, 152, 160, 152)
            } else {
                set_foreground(font.texture, 55, 59, 65)
            }

            line_number_str := strings.right_justify(
                fmt.tprintf("{}", line_number + 1),
                len(size_test_str) + LINE_NUMBER_JUSTIFY,
                " ", context.temp_allocator,
            )

            pen.y += y_offset_for_centering
            draw_text(font, pen, line_number_str)
            pen.y += line_number_character_height + 3
        }

    } else {
        gutter_size = MINIMUM_GUTTER_PADDING
        set_background(0, 0, 0)
        draw_rect(0, 0, gutter_size, pane_height, true)
    }

    if pane.rect.x > 0 {
        set_background(55, 59, 65)
        draw_line(0, 0, 0, pane_height)
    }

    return
}

draw_rect :: #force_inline proc(x, y, w, h: i32, fill := true) {
    rect := make_rect(x, y, w, h)

    if fill {
        sdl.RenderFillRect(renderer, &rect)
    } else {
        sdl.RenderRect(renderer, &rect)
    }
}

draw_line :: #force_inline proc(x1, y1, x2, y2: i32) {
    sdl.RenderLine(renderer, f32(x1), f32(y1), f32(x2), f32(y2))
}

draw_text :: proc(font: ^Font, pen: Vector2, text: string) -> (pen2: Vector2) {
    sx, sy := pen.x, pen.y

    for r in text {
        if r == '\t' {
            sx += 4 * font.xadvance
            continue
        }

        if r == '\n' {
            sx = pen.x
            sy += get_line_height(font)
            continue
        }

        glyph := find_or_create_glyph(font, r)
        src := make_rect(glyph.x, glyph.y, glyph.w, glyph.h)
        dest := make_rect(sx, sy, glyph.w, glyph.h)
        draw_texture(font.texture, &src, &dest)
        sx += glyph.xadvance
    }

    return {sx, sy}
}
