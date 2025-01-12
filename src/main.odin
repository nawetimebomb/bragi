package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

TITLE   :: "Bragi"
VERSION :: 0

DEFAULT_LOAD_FONT_DATA :: #load("../res/font/firacode.ttf")
DEFAULT_LOAD_FONT_SIZE :: 48
DEFAULT_WINDOW_WIDTH  :: 1024
DEFAULT_WINDOW_HEIGHT :: 768

Vector2 :: distinct [2]int

Line :: string

Cursor :: struct {
    position: Vector2,
    region_enabled: bool,
    region_start: Vector2,
}

Buffer :: struct {
    name: string,
    filepath: string,
    modified: bool,
    lines: [dynamic]Line,
    cursor: Cursor,
}

Settings :: struct {
    default_font: bool,
    font: rl.Font,
    font_size: int,

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
    bragi.settings.font_size    = 18
    bragi.settings.font         =
        rl.LoadFontFromMemory(".ttf", raw_data(DEFAULT_LOAD_FONT_DATA),
                              i32(len(DEFAULT_LOAD_FONT_DATA)),
                              DEFAULT_LOAD_FONT_SIZE, nil, 0)
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

create_buffer :: proc(name: string) -> ^Buffer {
    b := Buffer{ name = name }
    b.lines = make([dynamic]Line, 1, 10)
    append(&bragi.buffers, b)
    return &bragi.buffers[len(bragi.buffers) - 1]
}

get_current_buffer :: proc() -> ^Buffer {
    return &bragi.buffers[bragi.current_buffer]
}

insert_char_at_point :: proc(buf: ^Buffer, char: rune) {
    builder := strings.builder_make(context.temp_allocator)
    row := buf.cursor.position.y
    strings.write_string(&builder, buf.lines[row])
    strings.write_rune(&builder, char)
    buf.lines[row] = strings.clone(strings.to_string(builder))
    buf.cursor.position.x += 1
}

delete_char_at_point :: proc(buf: ^Buffer) {
    buf.cursor.position.x -= 1

    if buf.cursor.position.x < 0 {
        buf.cursor.position.y -= 1

        if buf.cursor.position.y < 0 {
            buf.cursor.position.y = 0
        }

        buf.cursor.position.x = len(buf.lines[buf.cursor.position.y])

        return
    }

    builder := strings.builder_make(context.temp_allocator)
    row := buf.cursor.position.y
    strings.write_string(&builder, buf.lines[row])
    strings.pop_rune(&builder)
    buf.lines[row] = strings.clone(strings.to_string(builder))
}

check_for_key :: proc(key: rl.KeyboardKey) -> bool {
    return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
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

        if check_for_key(.ENTER) {
            buf := get_current_buffer()
            buf.cursor.position.y += 1
            buf.cursor.position.x = 0

            if buf.cursor.position.y >= len(buf.lines) {
                append(&buf.lines, "")
            }
        }

        if check_for_key(.BACKSPACE) {
            buf := get_current_buffer()
            delete_char_at_point(buf)
        }

        char := rl.GetCharPressed()

        for char != 0 {
            insert_char_at_point(get_current_buffer(), char)
            char = rl.GetCharPressed()
        }

        rl.BeginTextureMode(bragi.render_texture)
        {
            rl.ClearBackground(rl.RAYWHITE)
            buf := get_current_buffer()
            font_size := f32(bragi.settings.font_size)

            for line, index in buf.lines {
                rl.DrawTextEx(bragi.settings.font, strings.clone_to_cstring(line),
                              {0, f32(index) * font_size}, font_size, 0, rl.BLACK)
            }

            line_text := strings.clone_to_cstring(buf.lines[buf.cursor.position.y])
            cursor_x := rl.MeasureText(line_text, i32(font_size)) - 1
            cursor_y := i32(buf.cursor.position.y) * i32(font_size)
            rl.DrawRectangle(cursor_x, cursor_y, 2,
                             i32(bragi.settings.font_size), rl.BLACK)
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

        free_all(context.temp_allocator)
    }

    rl.CloseWindow()
}
