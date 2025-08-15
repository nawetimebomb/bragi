package main

import     "core:log"

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

draw_rect :: proc(font: ^Font, pen: [2]f32, fill: bool) {
    if fill {
        rect := Rect{pen.x, pen.y, 2, f32(font.character_height)}
        set_background(205, 149, 12)
        sdl.RenderFillRect(renderer, &rect)
    }
}

draw_text :: proc(font: ^Font, pen: [2]f32, text: string) -> (pen2: [2]f32) {
    sx, sy := i32(pen.x), i32(pen.y)

    for r in text {
        if r == '\t' {
            sx += 4 * font.xadvance
            continue
        }

        if r == '\n' {
            sx = i32(pen.x)
            sy += get_line_height(font)
            continue
        }

        glyph := find_or_create_glyph(font, r)
        src := make_rect(glyph.x, glyph.y, glyph.w, glyph.h)
        dest := make_rect(sx, sy, glyph.w, glyph.h)
        set_foreground(font.texture, 255, 255, 255)
        draw_texture(font.texture, &src, &dest)
        sx += glyph.xadvance
    }

    return {f32(sx), f32(sy)}
}
