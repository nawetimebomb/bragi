package main

import     "core:fmt"
import     "core:log"
import     "core:os"
import     "core:unicode/utf8"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

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

platform_init_fonts :: proc() {
    profiling_start("platform.odin:platform_init_fonts")
    log.debug("Initializing fonts...")
    // TODO: Support fonts from the user configuration
    font_editor_data  := sdl.RWFromConstMem(raw_data(FONT_EDITOR), i32(len(FONT_EDITOR)))
    font_ui_data      := sdl.RWFromConstMem(raw_data(FONT_UI), i32(len(FONT_UI)))
    font_ui_bold_data := sdl.RWFromConstMem(raw_data(FONT_UI_BOLD), i32(len(FONT_UI)))

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

platform_deinit_fonts :: proc() {
    profiling_start("platform.odin:platform_deinit_fonts")
    log.debug("Deinitializing fonts...")

    delete(font_editor.name)
    ttf.CloseFont(font_editor.face)
    sdl.DestroyTexture(font_editor.texture)

    delete(font_ui.name)
    ttf.CloseFont(font_ui.face)
    sdl.DestroyTexture(font_ui.texture)

    delete(font_ui_bold.name)
    ttf.CloseFont(font_ui_bold.face)
    sdl.DestroyTexture(font_ui_bold.texture)

    log.debug("Font deinitialization complete")
    profiling_end()
}
