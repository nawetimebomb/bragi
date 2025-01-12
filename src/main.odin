package main

import    "base:runtime"
import    "core:fmt"
import    "core:strings"
import    "core:unicode/utf8"
import    "vendor:glfw"
import gl "vendor:OpenGL"

TITLE   :: "Bragi"
VERSION :: 0

DEFAULT_LOAD_FONT_DATA :: #load("../res/font/firacode.ttf")
DEFAULT_LOAD_FONT_SIZE :: 48
DEFAULT_WINDOW_WIDTH   :: 1024
DEFAULT_WINDOW_HEIGHT  :: 768

GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 3
GL_VSYNC_ENABLED :: 1

Vector2 :: distinct [2]int

Line :: string

Cursor :: struct {
    position:       Vector2,
    region_enabled: bool,
    region_start:   Vector2,
}

Buffer :: struct {
    name:     string,
    filepath: string,
    modified: bool,
    lines:    [dynamic]Line,
    cursor:   Cursor,
}

Settings :: struct {
    default_font: bool,
    font_size:    int,

    cursor_blink_delay_in_seconds: f32,
}

Bragi :: struct {
    cbuffer:  ^Buffer,
    buffers:  [dynamic]Buffer,

    settings: Settings,
    window:   glfw.WindowHandle,
}

bragi: Bragi

load_settings :: proc() {
    // TODO: Settings should be coming from a file or smth
    bragi.settings.default_font = true
    bragi.settings.font_size    = 18
    //    bragi.settings.font         =
}

configure_window :: proc() {
    bragi.window = {}
}

create_buffer :: proc(buf_name: string) -> ^Buffer {
    buf := Buffer{ name = buf_name }
    buf.lines = make([dynamic]Line, 1, 10)
    append(&bragi.buffers, buf)
    return &bragi.buffers[len(bragi.buffers) - 1]
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

// handle_input :: proc() {
//     if check_for_key(.ENTER) {
//         buf := bragi.cbuffer
//         buf.cursor.position.y += 1
//         buf.cursor.position.x = 0

//         if buf.cursor.position.y >= len(buf.lines) {
//             append(&buf.lines, "")
//         }
//     }

//     if check_for_key(.BACKSPACE) {
//         buf := bragi.cbuffer
//         delete_char_at_point(buf)
//     }

//     char := rl.GetCharPressed()

//     for char != 0 {
//         insert_char_at_point(bragi.cbuffer, char)
//         char = rl.GetCharPressed()
//     }
// }

handle_key_input :: proc "c" (w: glfw.WindowHandle, key, scancode, action, mods: i32) {
    if action == glfw.PRESS && key == glfw.KEY_ESCAPE {
        glfw.SetWindowShouldClose(w, true)
    }
}

handle_char_input:: proc "c" (w: glfw.WindowHandle, char: rune) {
    context = runtime.default_context()
    fmt.println(char)
}

handle_window_refresh :: proc "c" (w: glfw.WindowHandle) {
    context = runtime.default_context()
    w, h := glfw.GetFramebufferSize(bragi.window)
    gl.Viewport(0, 0, w, h)
    // TODO: re-render the screen
}

main :: proc() {
    load_settings()
    bragi.cbuffer = create_buffer("*notebook*")

    glfw.Init()

    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

    bragi.window = glfw.CreateWindow(DEFAULT_WINDOW_WIDTH,
                                     DEFAULT_WINDOW_HEIGHT,
                                     TITLE, nil, nil)
    assert(bragi.window != nil)

    glfw.MakeContextCurrent(bragi.window)
    glfw.SwapInterval(GL_VSYNC_ENABLED)
    gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)

    w, h := glfw.GetFramebufferSize(bragi.window)
    gl.Viewport(0, 0, w, h)

    glfw.SetCharCallback(bragi.window, handle_char_input)
    glfw.SetWindowRefreshCallback(bragi.window, handle_window_refresh)

    for !glfw.WindowShouldClose(bragi.window) {
        gl.ClearColor(0.0, 0.13, 0.15, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        glfw.SwapBuffers(bragi.window)
        glfw.PollEvents()
        free_all(context.temp_allocator)
    }

    glfw.DestroyWindow(bragi.window)
    glfw.Terminate()
}
