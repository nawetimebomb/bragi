package main

import     "core:log"
import     "core:strings"
import     "core:unicode/utf8"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

Font_Face :: enum {
    Editor,
    UI,
    UI_Bold,
    UI_Small,
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
    face:                    ^ttf.Font,
    glyphs_map:              map[rune]^Glyph_Data,
    texture:                 ^Texture,
    last_packed_glyph:       ^Glyph_Data,

    em_width:                i32,
    character_height:        i32,
    line_spacing:            i32,
    max_ascender:            i32,
    typical_ascender:        i32,
    max_descender:           i32,
    typical_descender:       i32,
    xadvance:                i32,
    y_offset_for_centering:  f32,
    replacement_character:   rune,
}

// NOTE(nawe) maximum number of glyphs we can cache. This should be
// sufficient for when working with code and editing text, but it
// might need to grow according to experience in using the editor.
MAX_SAFE_GLYPHS   :: 400
BASE_TEXTURE_SIZE :: MAX_SAFE_GLYPHS * 3

CHAR_PADDING :: 1

@(private="file")
fonts_initialized := false

@(private="file")
fonts_cache: [dynamic]^Font

fonts_map:   map[Font_Face]^Font

fonts_init :: proc() {
    log.debug("initializing fonts")
    success := ttf.Init()
    assert(success)
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
        ttf.CloseFont(font.face)
        free(font)
    }

    delete(fonts_cache)
    delete(fonts_map)
    ttf.Quit()
}

ensure_fonts_are_initialized :: #force_inline proc() {
    if !fonts_initialized do fonts_init()
}

initialize_font_related_stuff :: proc() {
    COMMON_CHARACTERS :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789~!@#$%^&*()-|\"':;_+={}[]\\/`,.<>? "

    scaled_font_editor_size := i32(f32(font_editor_size) * dpi_scale)
    scaled_font_ui_size     := i32(f32(font_ui_size) * dpi_scale)

    fonts_map[.Editor]   = get_font_with_size(FONT_EDITOR_NAME,  FONT_EDITOR_DATA,  scaled_font_editor_size)
    fonts_map[.UI]       = get_font_with_size(FONT_UI_NAME,      FONT_UI_DATA,      scaled_font_ui_size)
    fonts_map[.UI_Bold]  = get_font_with_size(FONT_UI_BOLD_NAME, FONT_UI_BOLD_DATA, scaled_font_ui_size)
    fonts_map[.UI_Small] = get_font_with_size(FONT_UI_NAME,      FONT_UI_DATA,      scaled_font_ui_size - 6)

    prepare_text(fonts_map[.Editor],  COMMON_CHARACTERS)
    prepare_text(fonts_map[.UI],      COMMON_CHARACTERS)
    prepare_text(fonts_map[.UI_Bold], COMMON_CHARACTERS)
}

get_font_with_size :: proc(name: string, data: []byte, character_height: i32) -> ^Font {
    ensure_fonts_are_initialized()

    for font in fonts_cache {
        if font.character_height != character_height do continue
        if font.name != name do continue
        return font
    }

    font_data := sdl.IOFromMem(raw_data(data), len(data))
    face := ttf.OpenFontIO(font_data, true, f32(character_height))

    result := new(Font, bragi_allocator)
    // TODO(nawe) maybe I don't need to clone this but I would guess,
    // if I ever allow to change it, I might just temporary load this
    // from a config and would need to clone it. It should be a small
    // string though.
    result.name = strings.clone(name)
    result.face = face
    result.replacement_character = 0xFFFD

    result.character_height =  ttf.GetFontHeight(result.face)
    result.max_ascender =  ttf.GetFontAscent(result.face)
    result.max_descender =  -ttf.GetFontDescent(result.face)

    // NOTE(nawe) I read somewhere that SDL_ttf sometimes has a bug
    // with some fonts where it cannot calculate the character height
    // correctly. Sadly I didn't capture the link for it but I had
    // this code around from before.
    if result.character_height < result.max_ascender - result.max_descender {
        result.character_height = result.max_ascender - result.max_descender
    }

    result.texture = texture_create(.STREAMING, BASE_TEXTURE_SIZE, BASE_TEXTURE_SIZE)

    minx, maxx, xadvance: i32
    _ = ttf.GetGlyphMetrics(result.face, u32('M'), &minx, &maxx, nil, nil, &xadvance)
    result.xadvance = xadvance
    result.em_width = minx + maxx

    if !ttf.FontHasGlyph(face, u32(result.replacement_character)) {
        result.replacement_character = 0x2022

        if !ttf.FontHasGlyph(face, u32(result.replacement_character)) {
            result.replacement_character = '?'
        }
    }

    append(&fonts_cache, result)
    return result
}

prepare_text :: proc(font: ^Font, text: string) -> (width_in_pixels: i32) {
    for r in text {
        glyph := find_or_create_glyph(font, r)
        width_in_pixels += glyph.xadvance
    }

    return
}

find_or_create_glyph :: proc(font: ^Font, r: rune) -> ^Glyph_Data {
    glyph, ok := font.glyphs_map[r]
    if ok do return glyph

    if !ttf.FontHasGlyph(font.face, u32(r)) {
        return find_or_create_glyph(font, font.replacement_character)
    }

    x, y, width, height: i32

    if font.last_packed_glyph != nil {
        x, y = font.last_packed_glyph.x, font.last_packed_glyph.y
        width, height = font.last_packed_glyph.w, font.last_packed_glyph.h
        x += width
    }

    result := new(Glyph_Data, bragi_allocator)

    surface := sdl.CreateSurface(BASE_TEXTURE_SIZE, BASE_TEXTURE_SIZE, .RGBA32)
    sdl.SetSurfaceColorKey(surface, true, sdl.MapSurfaceRGBA(surface, 0, 0, 0, 0))

    sdl.LockTextureToSurface(font.texture, nil, &surface)

    str_from_rune := utf8.runes_to_string([]rune{r}, context.temp_allocator)
    cstr := cstring(raw_data(str_from_rune))

    if x + width + CHAR_PADDING >= BASE_TEXTURE_SIZE {
        x = 0
        y += height + CHAR_PADDING

        if y + height >= BASE_TEXTURE_SIZE {
            log.fatalf("there's no space in texture to store rune '{}'", r)
        }
    }

    rect := sdl.Rect{x, y, width, height}

    _ = ttf.GetGlyphMetrics(font.face, u32(r), nil, nil, nil, nil, &result.xadvance)
    _ = ttf.GetStringSize(font.face, cstr, len(cstr), &rect.w, &rect.h)

    blended_text := ttf.RenderGlyph_Blended(font.face, u32(r), {255, 255, 255, 255})
    sdl.BlitSurface(blended_text, nil, surface, &rect)

    result.x = rect.x
    result.y = rect.y
    result.w = rect.w
    result.h = rect.h

    sdl.UnlockTexture(font.texture)

    font.glyphs_map[r] = result
    font.last_packed_glyph = result
    return result
}

get_line_height :: #force_inline proc(font: ^Font) -> i32 {
    return font.character_height + font.line_spacing
}
