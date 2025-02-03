package main

import     "core:fmt"
import     "core:log"
import     "core:mem"
import     "core:os"
import     "core:unicode/utf8"
import sdl "vendor:sdl2"
import stt "vendor:stb/truetype"
import ttf "vendor:sdl2/ttf"

// _Font :: struct {
//     ascent:      i32,
//     baseline:    i32,
//     chars:       [NUM_GLYPHS]stt.packedchar
//     em_width:    i32,
//     info:        stt.fontinfo,
//     line_height: i32,
//     scale:       f32,
//     size:        f32,
//     texture:     ^sdl.Texture
//     xadvance:    i32,
// }

@(private="file")
prepare_font :: proc(font: ^_Font, font_data: []u8, size: f32) -> mem.Allocator_Error {
    // TODO: Check this: https://gist.github.com/benob/92ee64d9ffcaa5d3be95edbf4ded55f2?permalink_comment_id=3806268
    ttf_buffer := raw_data(font_data)

    if stt.InitFont(&font.info, ttf_buffer, 0) == false {
        log.error("error loading font")
    }

    font.texture_size = 32
    bitmap: []u8

    for {
        bitmap = make([]u8, int(font.texture_size * font.texture_size))
        pack_context: stt.pack_context
        stt.PackBegin(&pack_context, raw_data(bitmap[:]), font.texture_size, font.texture_size, 0, 0, nil)
        stt.PackSetOversampling(&pack_context, 2, 2)

        if stt.PackFontRange(&pack_context, ttf_buffer, 0, size, 32, 95, raw_data(font.chars[:])) == 0 {
            // @ERROR: need to allocate more space because the font will not fit this buffer
            delete(bitmap)
            stt.PackEnd(&pack_context)
            font.texture_size *= 2
        } else {
            stt.PackEnd(&pack_context)
            break
        }
    }

    font.texture = sdl.CreateTexture(
        renderer, .RGBA32, .STATIC, font.texture_size, font.texture_size,
    )
    sdl.SetTextureBlendMode(font.texture, .BLEND)

    pixels := make([]u32, font.texture_size * font.texture_size * size_of(u32))
    format := sdl.AllocFormat(u32(sdl.PixelFormatEnum.RGBA32))

    for i := 0; i < int(font.texture_size * font.texture_size); i += 1 {
        pixels[i] = sdl.MapRGBA(format, 0xff, 0xff, 0xff, bitmap[i])
    }

    sdl.UpdateTexture(
        font.texture, nil, raw_data(pixels), font.texture_size * size_of(u32),
    )

    stt.GetFontVMetrics(&font.info, &font.ascent, &font.descent, &font.line_gap)
    font.em_width = f32(font.chars[45].x1 - font.chars[45].x0)
    font.scale = stt.ScaleForPixelHeight(&font.info, size)
    font.baseline = font.ascent * i32(font.scale)
    font.line_height = f32(font.ascent - font.descent + font.line_gap) * font.scale

    // ascent is the coordinate above the baseline the font extends; descent is the coordinate below the baseline the font extends (i.e. it is typically negative) lineGap is the spacing between one row's descent and the next row's ascent... so you should advance the vertical position by "ascent - descent + *lineGap" these are expressed in unscaled coordinates, so you must multiply by the scale factor for a given size

    delete(bitmap)
    delete(pixels)

    return nil
}

@(private="file")
map_glyphs_in_font :: proc(font: ^Font) {
    FONT_TEXTURE_SIZE :: 512

    base_surface := sdl.CreateRGBSurface(
        0, FONT_TEXTURE_SIZE, FONT_TEXTURE_SIZE, 32, 0, 0, 0, 255,
    )
    rect := sdl.Rect{}

    sdl.SetColorKey(base_surface, 1, sdl.MapRGBA(base_surface.format, 0, 0, 0, 0))

    for r := ' '; r <= '~'; r += 1 {
        str_from_rune := utf8.runes_to_string([]rune{r}, context.temp_allocator)
        cstr := cstring(raw_data(str_from_rune))
        text_surface := ttf.RenderGlyph32_Blended(font.face, r, { 255, 255, 255, 255 })
        ttf.SizeUTF8(font.face, cstr, &rect.w, &rect.h)

        if (rect.x + rect.w >= FONT_TEXTURE_SIZE) {
            rect.x = 0
            rect.y += rect.h + 1

            if (rect.y + rect.h >= FONT_TEXTURE_SIZE) {
                log.errorf("Out of glyph space in texture for font {0}", font.name)
                os.exit(1)
            }
        }

        sdl.BlitSurface(text_surface, nil, base_surface, &rect)

        font.glyphs[r].rect = rect
        rect.x += rect.w

        sdl.FreeSurface(text_surface)
    }

    font.em_width     = rect.w
    font.line_height  = ttf.FontHeight(font.face)
    font.texture      = sdl.CreateTextureFromSurface(renderer, base_surface)
    font.texture_size = FONT_TEXTURE_SIZE
    ttf.GlyphMetrics32(font.face, 'M', nil, nil, nil, nil, &font.x_advance)

    sdl.FreeSurface(base_surface)
}

increase_font_size :: proc() {
    font_editor_size = clamp(font_editor_size + 8, MINIMUM_FONT_SIZE, MAXIMUM_FONT_SIZE)
    ttf.SetFontSize(font_editor.face, font_editor_size)
    map_glyphs_in_font(&font_editor)

    char_width     = font_editor.em_width
    char_x_advance = font_editor.x_advance
    line_height    = font_editor.line_height
}

decrease_font_size :: proc() {
    font_editor_size = clamp(font_editor_size - 8, MINIMUM_FONT_SIZE, MAXIMUM_FONT_SIZE)
    ttf.SetFontSize(font_editor.face, font_editor_size)
    map_glyphs_in_font(&font_editor)

    char_width     = font_editor.em_width
    char_x_advance = font_editor.x_advance
    line_height    = font_editor.line_height
}

reset_font_size :: proc() {
    // TODO: Should actually use the font size from the settings
    font_editor_size = DEFAULT_FONT_EDITOR_SIZE
    ttf.SetFontSize(font_editor.face, font_editor_size)
    map_glyphs_in_font(&font_editor)

    char_width     = font_editor.em_width
    char_x_advance = font_editor.x_advance
    line_height    = font_editor.line_height
}

fonts_init :: proc() {
    profiling_start("fonts.odin:fonts_init")
    log.debug("Initializing fonts...")
    // TODO: Support fonts from the user configuration
    font_editor_data  := sdl.RWFromConstMem(raw_data(FONT_EDITOR), i32(len(FONT_EDITOR)))
    font_ui_data      := sdl.RWFromConstMem(raw_data(FONT_UI), i32(len(FONT_UI)))
    font_ui_bold_data := sdl.RWFromConstMem(raw_data(FONT_UI_BOLD), i32(len(FONT_UI)))

    prepare_font(&_font_editor, FONT_EDITOR, f32(font_editor_size))

    font_editor.face = ttf.OpenFontRW(font_editor_data, true, font_editor_size)
    assert(font_editor.face != nil, sdl.GetErrorString())
    font_editor.name = string(ttf.FontFaceFamilyName(font_editor.face))
    map_glyphs_in_font(&font_editor)

    font_ui.face = ttf.OpenFontRW(font_ui_data, true, font_ui_size)
    assert(font_ui.face != nil, sdl.GetErrorString())
    font_ui.name = string(ttf.FontFaceFamilyName(font_ui.face))
    map_glyphs_in_font(&font_ui)

    font_ui_bold.face = ttf.OpenFontRW(font_ui_bold_data, true, font_ui_size)
    assert(font_ui_bold.face != nil, sdl.GetErrorString())
    font_ui_bold.name = string(ttf.FontFaceFamilyName(font_ui_bold.face))
    ttf.SetFontStyle(font_ui_bold.face, ttf.STYLE_BOLD)
    map_glyphs_in_font(&font_ui_bold)

    char_width     = font_editor.em_width
    char_x_advance = font_editor.x_advance
    line_height    = font_editor.line_height

    log.debug("Fonts initialization complete")
    profiling_end()
}

fonts_deinit :: proc() {
    profiling_start("fonts.odin:fonts_deinit")
    log.debug("Deinitializing fonts...")

    sdl.DestroyTexture(_font_editor.texture)
    //free(_font_editor.chars)

    ttf.CloseFont(font_editor.face)
    sdl.DestroyTexture(font_editor.texture)

    ttf.CloseFont(font_ui.face)
    sdl.DestroyTexture(font_ui.texture)

    ttf.CloseFont(font_ui_bold.face)
    sdl.DestroyTexture(font_ui_bold.texture)

    log.debug("Font deinitialization complete")
    profiling_end()
}
