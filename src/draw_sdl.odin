package main

import     "core:log"
import     "core:unicode/utf8"

import sdl "vendor:sdl3"

Surface :: sdl.Surface
Texture :: sdl.Texture

make_texture :: #force_inline proc(access: sdl.TextureAccess, w, h: i32) -> ^Texture {
    return sdl.CreateTexture(renderer, .RGBA32, access, w, h)
}

draw_frame :: proc() {
    sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
    sdl.RenderClear(renderer)

    text := "Bragi Editor B̶͗͑̔̂͝"
    sx, sy: f32
    font := fonts_map[.Editor]

    for r in text {
        glyph := find_or_create_glyph(font, r)

        if glyph == nil {
            log.fatalf("cannot render glyph '{}'", r)
            continue
        }

        src := sdl.FRect{f32(glyph.x), f32(glyph.y), f32(glyph.w), f32(glyph.h)}
        dest := sdl.FRect{
            sx + f32(glyph.xoffset), sy + f32(glyph.yoffset) - font.y_offset_for_centering,
            f32(glyph.w), f32(glyph.h),
        }

        sdl.SetTextureColorMod(font.texture, 255, 255, 255)
        if !sdl.RenderTexture(renderer, font.texture, &src, &dest) {
            log.fatalf("failed to draw character '{}'", r)
        }
        sx += f32(glyph.xadvance)
    }

    sdl.RenderPresent(renderer)
}
