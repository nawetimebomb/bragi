package main

import     "core:log"
import     "core:unicode/utf8"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

@(private="file")
map_characters_for_font :: proc(font: ^Font) {
    COMMON_CHARS :: "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

    font.chars = make(map[rune]Char)

    for r in COMMON_CHARS {
        str_from_rune := utf8.runes_to_string([]rune{r}, context.temp_allocator)
        cstr := cstring(raw_data(str_from_rune))
        surface := ttf.RenderGlyph32_Blended(font.face, r, { 255, 255, 255, 255 })
        texture := sdl.CreateTextureFromSurface(renderer, surface)
        sdl.SetTextureScaleMode(texture, .Best)
        rect := sdl.Rect{}
        ttf.SizeUTF8(font.face, cstr, &rect.w, &rect.h)

        font.chars[r] = Char{ rect = rect, texture = texture }
        sdl.FreeSurface(surface)
    }
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
    map_characters_for_font(&font_editor)

    font_ui.face = ttf.OpenFontRW(font_ui_data, true, font_ui_size)
    assert(font_ui.face != nil, sdl.GetErrorString())
    map_characters_for_font(&font_ui)

    font_ui_bold.face = ttf.OpenFontRW(font_ui_bold_data, true, font_ui_size)
    assert(font_ui_bold.face != nil, sdl.GetErrorString())
    map_characters_for_font(&font_ui_bold)
    ttf.SetFontStyle(font_ui_bold.face, ttf.STYLE_BOLD)

    log.debug("Fonts initialization complete")
    profiling_end()
}

platform_deinit_fonts :: proc() {
    profiling_start("platform.odin:platform_deinit_fonts")
    log.debug("Deinitializing fonts...")

    for _, char in font_editor.chars {
        sdl.DestroyTexture(char.texture)
    }

    delete(font_editor.chars)
    ttf.CloseFont(font_editor.face)

    for _, char in font_ui.chars {
        sdl.DestroyTexture(char.texture)
    }

    delete(font_ui.chars)
    ttf.CloseFont(font_ui.face)

    for _, char in font_ui_bold.chars {
        sdl.DestroyTexture(char.texture)
    }

    delete(font_ui_bold.chars)
    ttf.CloseFont(font_ui_bold.face)

    log.debug("Font deinitialization complete")
    profiling_end()
}
