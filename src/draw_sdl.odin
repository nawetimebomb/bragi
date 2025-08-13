package main

import     "core:log"

import sdl "vendor:sdl3"

Rect    :: sdl.FRect
Surface :: sdl.Surface
Texture :: sdl.Texture
Vector2 :: distinct [2]i32

Visible_Cursor :: struct {
    pos:           Vector2,
    sel:           Vector2,
    has_selection: bool,
}

texture_create :: #force_inline proc(access: sdl.TextureAccess, w, h: i32) -> ^Texture {
    return sdl.CreateTexture(renderer, .RGBA32, access, w, h)
}

texture_destroy :: #force_inline proc(texture: ^Texture) {
    sdl.DestroyTexture(texture)
}

prepare_for_drawing :: #force_inline proc() {
    sdl.RenderClear(renderer)
}

draw_frame :: #force_inline proc() {
    sdl.RenderPresent(renderer)
}

draw_rect :: #force_inline proc(font: ^Font, x, y: f32, fill: bool) {
    if fill {
        rect := Rect{x, y, 2, f32(font.character_height)}
        set_background(205, 149, 12)
        sdl.RenderFillRect(renderer, &rect)
    }
}

draw_texture :: #force_inline proc(texture: ^Texture, src, dest: ^Rect, loc := #caller_location) {
    if !sdl.RenderTexture(renderer, texture, src, dest) {
        log.errorf("failed to render texture at '{}'", loc)
    }
}

set_background :: #force_inline proc(r, g, b: u8) {
    sdl.SetRenderDrawColor(renderer, r, g, b, 255)
}

set_foreground :: #force_inline proc(texture: ^Texture, r, g, b: u8) {
    sdl.SetTextureColorMod(texture, r, g, b)
}

set_target :: #force_inline proc(target: ^Texture = nil) {
    sdl.SetRenderTarget(renderer, target)
}
