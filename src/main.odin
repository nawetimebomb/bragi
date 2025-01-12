package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

TITLE   :: "Bragi"
VERSION :: 0

DEFAULT_FONT_DATA :: #load("../res/font/firacode.ttf")
DEFAULT_WINDOW_WIDTH  :: 1024
DEFAULT_WINDOW_HEIGHT :: 768

Line :: string

Cursor :: struct {
    position: rl.Vector2,
    region_enabled: bool,
    region_start: rl.Vector2,
}

Buffer :: struct {
    name: string,
    filepath: string,
    modified: bool,
    lines: [dynamic]Line,
}

Settings :: struct {
    default_font: bool,
    font: rl.Font,
    font_size: uint,

    cursor_blink_delay_in_seconds: f32,
}

Window :: struct {
    width: i32,
    height: i32,
    fullscreen: bool,
    maximized: bool,
    hidpi: bool,
}

Bragi :: struct {
    cursor: Cursor,
    current_buffer: int,
    buffers: [dynamic]Buffer,

    render_texture: rl.RenderTexture,
    settings: Settings,
    window: Window,
}

bragi: Bragi

load_settings :: proc() {
    // TODO: Settings should be coming from a file or smth
    bragi.settings.default_font = true
    bragi.settings.font_size    = 16
    bragi.settings.font         =
        rl.LoadFontFromMemory(".ttf", raw_data(DEFAULT_FONT_DATA),
                              i32(len(DEFAULT_FONT_DATA)),
                              i32(bragi.settings.font_size), nil, 0)
}

configure_window :: proc() {
    bragi.window = {
        width = rl.GetScreenWidth(),
        height = rl.GetScreenHeight(),
        fullscreen = rl.IsWindowFullscreen(),
        maximized = rl.IsWindowMaximized(),
    }
}

create_render_texture :: proc() {
    if rl.IsRenderTextureValid(bragi.render_texture) {
        rl.UnloadRenderTexture(bragi.render_texture)
    }

    bragi.render_texture = rl.LoadRenderTexture(bragi.window.width, bragi.window.height)
    rl.SetTextureFilter(bragi.render_texture.texture, .BILINEAR)
    rl.SetTextureWrap(bragi.render_texture.texture, .CLAMP)
}

create_buffer :: proc(name: string) {
    b := Buffer{ name = name }
    b.lines = make([dynamic]Line, 1, 10)
    append(&bragi.buffers, b)
}

get_current_buffer :: proc() -> ^Buffer {
    return &bragi.buffers[bragi.current_buffer]
}

main :: proc() {
    rl.SetConfigFlags({ .VSYNC_HINT, .WINDOW_RESIZABLE, .WINDOW_HIGHDPI })
    rl.SetTraceLogLevel(.WARNING)

    // TODO: This should actually be configured by the user.
    rl.InitWindow(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, TITLE)

    load_settings()
    configure_window()
    create_render_texture()

    create_buffer("*notebook*")

    for !rl.WindowShouldClose() {
        if rl.IsWindowResized() {
            configure_window()
            create_render_texture()
        }

        key_pressed := rl.GetCharPressed()

        for key_pressed != 0 {
            b := get_current_buffer()
            current_line := b.lines[0]
            new_value := utf8.runes_to_string([]rune{key_pressed})
            b.lines[0] = new_value

            fmt.println(key_pressed, b.lines)

            key_pressed = rl.GetCharPressed()
        }

        rl.BeginTextureMode(bragi.render_texture)
        {
            rl.ClearBackground(rl.RAYWHITE)
            b := get_current_buffer()
            font_size := f32(bragi.settings.font_size)

            for line, index in b.lines {
                rl.DrawTextEx(bragi.settings.font,
                              strings.clone_to_cstring(line),
                              {0, f32(index) * font_size}, font_size, 0, rl.BLACK)
            }
        }
        rl.EndTextureMode()

        rl.BeginDrawing()
        {
            fbw := f32(bragi.render_texture.texture.width)
            fbh := f32(bragi.render_texture.texture.height)
            dest_rect := rl.Rectangle{0, 0, fbw, fbh}
            src_rect := rl.Rectangle{0, 0, fbw, -fbh}
            rl.DrawTexturePro(bragi.render_texture.texture,
                              src_rect, dest_rect, {}, 0, rl.WHITE)
        }
        rl.EndDrawing()
    }

    rl.CloseWindow()
}
