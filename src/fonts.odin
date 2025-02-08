package main

import     "core:fmt"
import     "core:log"
import     "core:math"
import     "core:os"
import     "core:unicode/utf8"
import  ft "shared:freetype"
import sdl "vendor:sdl2"

NUM_GLYPHS :: 128

Glyph :: struct {
    x, y: i32,
    w, h: i32,
    xoffset: i32,
    yoffset: i32,
    xadvance: i32,
}

Font :: struct {
    em_width: i32,
    face: ft.Face,
    glyphs: [NUM_GLYPHS]Glyph,
    line_height: i32,
    texture: ^sdl.Texture,
    y_offset_for_centering: f32,
}

@(private="file")
library: ft.Library

fonts_init :: proc() {
    profiling_start("fonts.odin:fonts_init")
    log.debug("Initializing fonts...")

    ft.init_free_type(&library)
    font_editor  = prepare_font(FONT_EDITOR,  font_editor_size)
    font_ui      = prepare_font(FONT_UI,      font_ui_size)
    font_ui_bold = prepare_font(FONT_UI_BOLD, font_ui_size)

    char_width             = font_editor.em_width
    line_height            = font_editor.line_height
    y_offset_for_centering = font_editor.y_offset_for_centering

    log.debug("Fonts initialization complete")
    profiling_end()
}

fonts_deinit :: proc() {
    profiling_start("fonts.odin:fonts_deinit")
    log.debug("Deinitializing fonts...")

    ft.done_face(font_editor.face)
    sdl.DestroyTexture(font_editor.texture)
    ft.done_face(font_ui.face)
    sdl.DestroyTexture(font_ui.texture)
    ft.done_face(font_ui_bold.face)
    sdl.DestroyTexture(font_ui_bold.texture)
    ft.done_free_type(library)

    log.debug("Font deinitialization complete")
    profiling_end()
}

get_width_based_on_text_size :: proc(f: Font, s: string, dwidth: int) -> (size: i32) {
    delta := dwidth - len(s)
    size = get_text_size(f, s)
    if delta > 0 { size += i32(delta) * f.em_width }
    return
}

get_text_size :: proc(f: Font, s: string) -> (size: i32) {
    for r in s {
        g := f.glyphs[r]
        // TODO: add support for invalid glyph
        size += g.xadvance
    }
    return
}

increase_font_size :: proc() {
    MAX_FONT_SIZE :: 144

    if font_editor_size < MAX_FONT_SIZE {
        font_editor_size = auto_cast min(f32(font_editor_size) * 1.2, MAX_FONT_SIZE)
        assert(ft.set_pixel_sizes(font_editor.face, 0, font_editor_size) == .Ok, "Can't set pixel size")
        generate_font_bitmap_texture(&font_editor)

        char_width             = font_editor.em_width
        line_height            = font_editor.line_height
        y_offset_for_centering = font_editor.y_offset_for_centering
    }
}

decrease_font_size :: proc() {
    MIN_FONT_SIZE :: 8

    if font_editor_size > MIN_FONT_SIZE {
        font_editor_size = auto_cast max(f32(font_editor_size) * 0.8, MIN_FONT_SIZE)
        assert(ft.set_pixel_sizes(font_editor.face, 0, font_editor_size) == .Ok, "Can't set pixel size")
        generate_font_bitmap_texture(&font_editor)

        char_width             = font_editor.em_width
        line_height            = font_editor.line_height
        y_offset_for_centering = font_editor.y_offset_for_centering
    }
}

reset_font_size :: proc() {
    // TODO: Should actually use the font size from the settings
    font_editor_size = DEFAULT_FONT_EDITOR_SIZE
    assert(ft.set_pixel_sizes(font_editor.face, 0, font_editor_size) == .Ok, "Can't set pixel size")
    generate_font_bitmap_texture(&font_editor)

    char_width             = font_editor.em_width
    line_height            = font_editor.line_height
    y_offset_for_centering = font_editor.y_offset_for_centering
}

@(private="file")
generate_font_bitmap_texture :: proc(result: ^Font) {
    // Clean-up previous texture
    sdl.DestroyTexture(result.texture)

    result.line_height = i32((result.face.size.metrics.ascender - result.face.size.metrics.descender) >> 6)

    // TODO: I'm trying to figure out the size of the texture to be created, but this is super slow and it's taken from the link below:
    // https://gist.github.com/baines/b0f9e4be04ba4e6f56cab82eef5008ff#file-freetype-atlas-c-L28
    // I need to find a better way to do this.
    texture_dimensions := f32(1 + (result.face.size.metrics.height >> 6)) * math.ceil_f32(math.sqrt_f32(NUM_GLYPHS))
    texture_size : i32 = 1
    for f32(texture_size) < texture_dimensions { texture_size <<= 1 }

    full_bitmap := make([]byte, texture_size * texture_size)
    pos_x, pos_y: i32

    for i: u32 = 0; i < NUM_GLYPHS; i += 1 {
        ft.load_char(result.face, i, {.Render, .Force_Autohint})
        char_bitmap := &result.face.glyph.bitmap

        if pos_x + i32(char_bitmap.width) >= texture_size {
            pos_x = 0
            pos_y += i32(result.face.size.metrics.height >> 6) + 1
        }

        for row: i32 = 0; row < i32(char_bitmap.rows); row += 1 {
            for col: i32 = 0; col < i32(char_bitmap.width); col += 1 {
                x := pos_x + col
                y := pos_y + row
                full_bitmap[y * texture_size + x] =
                    char_bitmap.buffer[row * char_bitmap.pitch + col]
            }
        }

        result.glyphs[i].x = pos_x
        result.glyphs[i].y = pos_y
        result.glyphs[i].w = i32(char_bitmap.width)
        result.glyphs[i].h = i32(char_bitmap.rows)
        result.glyphs[i].xoffset = result.face.glyph.bitmap_left
        result.glyphs[i].yoffset = result.line_height - result.face.glyph.bitmap_top
        result.glyphs[i].xadvance = i32(result.face.glyph.advance.x >> 6)

        pos_x += i32(char_bitmap.width) + 1
    }

    // Using the 'm' glyph for centering
    glyph_index := ft.get_char_index(result.face, 'm')
    ft.load_glyph(result.face, glyph_index, {})
    result.y_offset_for_centering =
        0.5 * f32(result.face.glyph.metrics.hori_bearing_y >> 6) + 0.5

    // Using the 'M' glyph for em_width
    glyph_index = ft.get_char_index(result.face, 'M')
    ft.load_glyph(result.face, glyph_index, {})
    result.em_width = i32(result.face.glyph.bitmap.width)

    pixels := make([]u32, texture_size * texture_size)
    format := sdl.AllocFormat(u32(sdl.PixelFormatEnum.RGBA32))
    result.texture = sdl.CreateTexture(renderer, .RGBA32, .STATIC, texture_size, texture_size)

    sdl.SetTextureBlendMode(result.texture, .BLEND)

    for i := 0; i < int(texture_size * texture_size); i += 1 {
        pixels[i] = sdl.MapRGBA(format, 255, 255, 255, full_bitmap[i])
    }

    sdl.UpdateTexture(result.texture, nil, raw_data(pixels), texture_size * size_of(u32))

    delete(full_bitmap)
    delete(pixels)
}

@(private="file")
prepare_font :: proc(font_data: []byte, size: u32) -> Font {
    result: Font

    assert(ft.new_memory_face(library, raw_data(font_data), i32(len(font_data)), 0, &result.face) == .Ok, "Can't load font")
    assert(ft.set_pixel_sizes(result.face, 0, size) == .Ok, "Can't set pixel size")
    generate_font_bitmap_texture(&result)
    return result
}

@(private="file")
prepare_font_from_filename :: proc(font: Font, filename: string, size: u32) {
    // TODO: Read entire file and call prepare_font
}
