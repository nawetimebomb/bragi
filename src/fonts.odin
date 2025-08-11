package main

import    "core:log"
import    "core:math"
import    "core:strings"

import "core:os"

import ft "freetype"

Font_Face :: enum {
    Editor,
    UI,
    UI_Bold,
}

Glyph_Data :: struct {
    x, y:     i32,
    w, h:     i32,
    xoffset:  i32,
    yoffset:  i32,
    xadvance: i32,
}

Font :: struct {
    name:                    string,
    face:                    ft.Face,
    glyphs_map:              map[rune]^Glyph_Data,
    texture:                 ^Texture,
    last_packed_glyph:       ^Glyph_Data,

    em_width:                i32,
    character_height:        i32,
    default_line_spacing:    i32,
    max_ascender:            i32,
    typical_ascender:        i32,
    max_descender:           i32,
    typical_descender:       i32,
    xadvance:                i32,
    y_offset_for_centering:  f32,
    missing_character:       rune,
}

// NOTE(nawe) maximum number of glyphs we can cache. This should be
// sufficient for when working with code and editing text, but it
// might need to grow according to experience in using the editor.
MAX_SAFE_GLYPHS   :: 400
// NOTE(nawe) I'm basically guessing this number below, but from
// experience, I would want to do something like `MAX_SAFE_GLYPHS *
// math.ceil(math.sqrt(FONT_SIZE))`, this should more than enough to
// store the amount of characters in MAX_SAFE_GLYPHS. Because it is
// more than enough, I'm not changing it with the font size and
// instead just using DEFAULT_EDITOR_FONT_SIZE.
BASE_TEXTURE_SIZE :: MAX_SAFE_GLYPHS

FONT_CHAR_PADDING :: 1

@(private="file")
ft_library: ft.Library
@(private="file")
fonts_initialized := false
// NOTE(nawe) used only internally to keep track of the loaded fonts
// (and different sizes). The reason why I load fonts again when
// changing size is because I'm very used to increase the size when
// working on some files or sharing screen, and since the font rarely
// changes on a text editor, we have sufficient space to cache all the
// sizes we need.
@(private="file")
fonts_cache: [dynamic]^Font

fonts_map:   map[Font_Face]^Font

fonts_init :: proc() {
    log.debug("initializing fonts")
    ft.init_free_type(&ft_library)
    fonts_initialized = true
}

fonts_destroy :: proc() {
    log.debug("deinitializing fonts")

    for font in fonts_cache {
        for _, glyph in font.glyphs_map {
            free(glyph)
        }

        delete(font.name)
        delete(font.glyphs_map)
        ft.done_face(font.face)
        free(font)
    }

    delete(fonts_cache)
    delete(fonts_map)

    ft.done_free_type(ft_library)
}

ensure_fonts_are_initialized :: #force_inline proc() {
    if !fonts_initialized do fonts_init()
}

get_font_with_size :: proc(name: string, data: []byte, character_height: i32) -> ^Font {
    ensure_fonts_are_initialized()

    for font in fonts_cache {
        if font.character_height != character_height do continue
        if font.name != name do continue
        return font
    }

    face: ft.Face
    if ft.new_memory_face(ft_library, raw_data(data), i64(len(data)), 0, &face) != .Ok {
        log.fatalf("failed to load font")
        return nil
    }

    result := new(Font, bragi_allocator)
    // TODO(nawe) maybe I don't need to clone this but I would guess,
    // if I ever allow to change it, I might just temporary load this
    // from a config and would need to clone it. It should be a small
    // string though.
    result.name = strings.clone(name)
    result.face = face
    result.character_height = character_height
    result.missing_character = 0xFFFD

    success := ft.set_pixel_sizes(result.face, 0, u32(character_height))
    assert(success == .Ok)

    y_scale_font_to_pixels := f32(face.size.metrics.y_scale/(64.0*65536.0))

    result.default_line_spacing = i32(math.floor(y_scale_font_to_pixels * f32(face.height) + 0.5))
    result.max_ascender  = i32(math.floor(y_scale_font_to_pixels * f32(face.bbox.y_max) + 0.5))
    result.max_descender = i32(math.floor(y_scale_font_to_pixels * f32(face.bbox.y_min) + 0.5))

    glyph_index := ft.get_char_index(face, 'm')
    ft.load_glyph(face, glyph_index, {})
    result.y_offset_for_centering = 0.5 * f32(ft.round(result.face.glyph.metrics.hori_bearing_y)) + 0.5

    glyph_index = ft.get_char_index(face, 'M')
    ft.load_glyph(face, glyph_index, {})
    result.em_width = i32(ft.round(result.face.glyph.bitmap.width))
    result.xadvance = i32(ft.round(result.face.glyph.advance.x))

    glyph_index = ft.get_char_index(face, 'T')
    ft.load_glyph(face, glyph_index, {})
    result.typical_ascender = i32(ft.round(face.glyph.metrics.hori_bearing_y))

    glyph_index = ft.get_char_index(face, 'g')
    result.typical_descender = i32(ft.round(face.glyph.metrics.hori_bearing_y - face.glyph.metrics.height))

    // making sure the default missing character exists
    glyph_index = ft.get_char_index(face, u64(result.missing_character))
    if glyph_index == 0 {
        result.missing_character = '?'
    }

    success = ft.select_charmap(face, .Unicode)
    if success != .Ok {
        log.fatalf("couldn't select unicode charmap for font {}", result.name)
    }

    result.texture = make_texture(.STREAMING, BASE_TEXTURE_SIZE, BASE_TEXTURE_SIZE)

    append(&fonts_cache, result)
    return result
}

initialize_font_related_stuff :: proc() {
    fonts_map[.Editor]  = get_font_with_size(FONT_EDITOR_NAME, FONT_EDITOR, font_editor_size)
    prepare_font(fonts_map[.Editor])

    fonts_map[.UI] = get_font_with_size(FONT_UI_NAME, FONT_UI, font_ui_size)
    prepare_font(fonts_map[.UI])

    fonts_map[.UI_Bold] = get_font_with_size(FONT_UI_BOLD_NAME, FONT_UI_BOLD, font_ui_size)
    prepare_font(fonts_map[.UI_Bold])
}

find_or_create_glyph :: proc(font: ^Font, r: rune) -> ^Glyph_Data {
    result, ok := font.glyphs_map[r]
    if ok do return result

    ft.load_char(font.face, u64(r), {.Force_Autohint, .Render})
    char_bitmap := &font.face.glyph.bitmap
    xadvance := i32(char_bitmap.width)
    x, y: i32

    if font.last_packed_glyph != nil {
        xadvance = font.last_packed_glyph.xadvance
        x = font.last_packed_glyph.x + xadvance + FONT_CHAR_PADDING
        y = font.last_packed_glyph.y
    }

    // bitmap := make([]byte, char_bitmap.width * char_bitmap.height, context.temp_allocator)

    // for row := 0; row < char_bitmap.rows; row += 1 {
    //     for col := 0; col < char_bitmap.width; col += 1 {
    //         bitmap[row * char_bitmap.width + col] = char_bitmap.buffer[row * char_bitmap.pitch + col]
    //     }
    // }

    surface := make_surface_for_text(font.texture.w, font.texture.h, .RGBA32)
    lock_texture(font.texture, &surface)

    if x + xadvance + FONT_CHAR_PADDING >= font.texture.w {
        x = 0
        y += font.character_height + FONT_CHAR_PADDING

        if y + i32(char_bitmap.rows) >= font.texture.h {
            log.fatalf("there's no more space in texture for {}", r)
        }
    }

    glyph := new(Glyph_Data)
    glyph.x = x
    glyph.y = y
    glyph.w = i32(char_bitmap.width)
    glyph.h = i32(char_bitmap.rows)
    glyph.xoffset  = font.face.glyph.bitmap_left
    glyph.yoffset  = font.character_height - font.face.glyph.bitmap_top
    glyph.xadvance = i32(ft.round(font.face.glyph.advance.x))

    blit_surface(r, surface, glyph.x, glyph.y, glyph.w, glyph.h)
    unlock_texture(font.texture)

    font.glyphs_map[r] = glyph
    font.last_packed_glyph = glyph
    return glyph
}

prepare_font :: proc(font: ^Font) {
    COMMON_CHARACTERS :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789~!@#$%^&*()-|\"':;_+={}[]\\/`,.<>? "

    full_bitmap := make([]byte, BASE_TEXTURE_SIZE * BASE_TEXTURE_SIZE, context.temp_allocator)
    x, y: i32
    count := 0

    for r in COMMON_CHARACTERS {
        _, ok := font.glyphs_map[r]
        if ok do continue

        ft.load_char(font.face, u64(r), {.Force_Autohint, .Render})
        char_bitmap := &font.face.glyph.bitmap

        if x + i32(char_bitmap.width) + FONT_CHAR_PADDING >= BASE_TEXTURE_SIZE {
            x = 0
            y += font.character_height + FONT_CHAR_PADDING

            if y + font.character_height + FONT_CHAR_PADDING >= BASE_TEXTURE_SIZE {
                log.fatalf("no space to prepare font {}", font.name)
            }
        }

        for row: i32 = 0; row < i32(char_bitmap.rows); row += 1 {
            for col: i32 = 0; col < i32(char_bitmap.width); col += 1 {
                x1 := x + col
                y1 := y + row
                full_bitmap[y1 * BASE_TEXTURE_SIZE + x1] =
                    char_bitmap.buffer[row * char_bitmap.pitch + col]
            }
        }

        glyph := new(Glyph_Data)
        glyph.x = x
        glyph.y = y
        glyph.w = i32(char_bitmap.width)
        glyph.h = i32(char_bitmap.rows)
        glyph.xoffset  = font.face.glyph.bitmap_left
        glyph.yoffset  = font.character_height - font.face.glyph.bitmap_top
        glyph.xadvance = i32(ft.round(font.face.glyph.advance.x))

        font.glyphs_map[r] = glyph

        x += i32(char_bitmap.width) + FONT_CHAR_PADDING
    }

    font.texture = prepare_texture_from_bitmap(
        font.texture, &full_bitmap, BASE_TEXTURE_SIZE, BASE_TEXTURE_SIZE,
    )
}

// prepare_text :: proc(font: ^Font, text: string) -> (width_in_pixels: i32) {
//     if len(text) == 0 {
//         return 0
//     }

//     for r in text {
//         glyph := find_or_create_glyph(font, r)

//         if glyph != nil {
//             width_in_pixels += glyph.xadvance
//         }
//     }

//     return
// }
