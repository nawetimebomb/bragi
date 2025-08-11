package main

import     "core:log"
import     "core:unicode/utf8"

import sdl "vendor:sdl3"

Surface :: sdl.Surface
Texture :: sdl.Texture

make_texture :: #force_inline proc(access: sdl.TextureAccess, w, h: i32) -> ^Texture {
    return sdl.CreateTexture(renderer, .RGBA32, access, w, h)
}

make_surface_for_text :: #force_inline proc(w, h: i32, format: sdl.PixelFormat) -> ^Surface {
    result := sdl.CreateSurface(w, h, format)
    sdl.SetSurfaceColorKey(result, true, sdl.MapSurfaceRGBA(result, 0, 0, 0, 0))
    return result
}

lock_texture :: #force_inline proc(texture: ^Texture, surface: ^^Surface) {
    if !sdl.LockTextureToSurface(texture, nil, surface) {
        log.fatal("couldn't lock texture", sdl.GetError())
    }
}

blit_surface :: #force_inline proc(r: rune, surface: ^Surface, x, y, w, h: i32) {
    rect := sdl.Rect{x, y, w, h}
    str_from_rune := utf8.runes_to_string([]rune{r}, context.temp_allocator)
    cstr := cstring(raw_data(str_from_rune))
    // blit_surface(cs, nil, surface, &rect)
}

unlock_texture :: #force_inline proc(texture: ^Texture) {
    sdl.UnlockTexture(texture)
}

prepare_texture_from_bitmap :: proc(texture: ^Texture, bitmap: ^[]byte, w, h: int) -> ^Texture {
    sdl.DestroyTexture(texture)
    result := sdl.CreateTexture(renderer, .RGBA32, .STATIC, i32(w), i32(h))
    pixels := make([]u32, w * h, context.temp_allocator)
    format := sdl.GetPixelFormatDetails(.RGBA32)
    sdl.SetTextureBlendMode(result, {.BLEND})

    for i := 0; i < w * h; i += 1 {
        pixels[i] = sdl.MapRGBA(format, nil, 255, 255, 255, bitmap[i])
    }

    sdl.UpdateTexture(texture, nil, raw_data(pixels), i32(w) * size_of(u32))
    return result
}

draw_frame :: proc() {
    sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
    sdl.RenderClear(renderer)

    text := "Bragi Editor"
    sx, sy: f32
    font := fonts_map[.Editor]

    for r in text {
        glyph, ok := font.glyphs_map[r]

        if !ok {
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
