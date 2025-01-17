package main

import     "base:runtime"
import     "core:fmt"
import     "core:log"
import     "core:mem"
import     "core:os"
import     "core:strings"
import     "core:unicode/utf8"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

TITLE   :: "Bragi"
VERSION :: 0

FPS :: 60

DEFAULT_FONT_DATA     :: #load("../res/font/firacode.ttf")
DEFAULT_FONT_SIZE     :: 22
DEFAULT_WINDOW_WIDTH  :: 1024
DEFAULT_WINDOW_HEIGHT :: 768
DEFAULT_CURSOR_BLINK  :: 1.0

Settings :: struct {
    font_size: i32,

    cursor_blink_delay_in_seconds : f32,
    remove_trailing_whitespaces   : bool,
    save_desktop_mode             : bool,
}

Character_Texture :: struct {
    texture : ^sdl.Texture,
    dest    : sdl.Rect,
}

SDL_Context :: struct {
    font         : ^ttf.Font,
    characters   : map[rune]Character_Texture,
    running      : bool,
    renderer     : ^sdl.Renderer,
    window       : ^sdl.Window,
    window_size  : Vector2,
}

Bragi :: struct {
    ctx          : SDL_Context,

    tbuffers     : [dynamic]Text_Buffer,
    panes        : [dynamic]Pane,
    focused_pane : int,
    keybinds     : Keybinds,

    buffers      : [dynamic]Buffer,
    cbuffer      : ^Buffer,
    settings     : Settings,
}

bragi: Bragi

initialize_sdl :: proc() {
    assert(sdl.Init({.VIDEO}) == 0, sdl.GetErrorString())
    assert(ttf.Init() == 0, sdl.GetErrorString())

    bragi.ctx.window =
        sdl.CreateWindow(TITLE, sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED,
                         DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT,
                         {.SHOWN, .RESIZABLE, .ALLOW_HIGHDPI})
    assert(bragi.ctx.window != nil, "Cannot open window")

    bragi.ctx.renderer =
        sdl.CreateRenderer(bragi.ctx.window, -1, {.ACCELERATED})
    assert(bragi.ctx.renderer != nil, "Cannot create renderer")

    bragi.ctx.font = ttf.OpenFont("../res/font/firacode.ttf", DEFAULT_FONT_SIZE)
    assert(bragi.ctx.font != nil, sdl.GetErrorString())

    bragi.ctx.running = true
    bragi.ctx.window_size = { DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT }
}

destroy_sdl :: proc() {
    for _, char in bragi.ctx.characters {
        sdl.DestroyTexture(char.texture)
    }
    delete(bragi.ctx.characters)

    sdl.DestroyRenderer(bragi.ctx.renderer)
    sdl.DestroyWindow(bragi.ctx.window)
    ttf.CloseFont(bragi.ctx.font)
    ttf.Quit()
    sdl.Quit()
}

// NOTE: This function should run every time the user changes the font
create_textures_for_characters :: proc() {
    COLOR_WHITE : sdl.Color : { 255, 255, 255, 255 }
    ascii := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

    for c in ascii[:] {
        ostr := utf8.runes_to_string([]rune{c})
        cstr := cstring(raw_data(ostr))
        surface := ttf.RenderGlyph32_Blended(bragi.ctx.font, c, COLOR_WHITE)
        texture := sdl.CreateTextureFromSurface(bragi.ctx.renderer, surface)
        sdl.SetTextureScaleMode(texture, .Best)
        dest_rect := sdl.Rect{}
        ttf.SizeUTF8(bragi.ctx.font, cstr, &dest_rect.w, &dest_rect.h)

        bragi.ctx.characters[c] = Character_Texture{
            texture = texture,
            dest    = dest_rect,
        }

        sdl.FreeSurface(surface)
        delete(ostr)
    }
}

get_standard_character_size :: proc() -> Vector2 {
    M_char_rect := bragi.ctx.characters['M'].dest
    return Vector2{ int(M_char_rect.w), int(M_char_rect.h) }
}

main :: proc() {
    context.logger = log.create_console_logger()

    default_allocator := context.allocator
    tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, default_allocator)
    context.allocator = mem.tracking_allocator(&tracking_allocator)

    reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
        err := false

        for _, value in a.allocation_map {
            fmt.printfln("{0}: Leaked {1} bytes", value.location, value.size)
            err = true
        }

        mem.tracking_allocator_clear(a)
        return err
    }

    editor_open()
    initialize_sdl()
    create_textures_for_characters()
    load_keybinds()

    for bragi.ctx.running {
        duration, dt_ms, frame_start, frame_end: u32
        dt_ms = 1000 / FPS
        e: sdl.Event

        frame_start = sdl.GetTicks()

        for sdl.PollEvent(&e) {
            #partial switch e.type {
                case .QUIT: bragi.ctx.running = false
                case .WINDOWEVENT: {
                    w := e.window

                    if w.event == .RESIZED && w.data1 != 0 && w.data2 != 0 {
                        bragi.ctx.window_size = {
                            int(e.window.data1),
                            int(e.window.data2),
                        }
                    }
                }
                case .DROPFILE: {
                    filepath := string(e.drop.file)
                    bragi.cbuffer = editor_maybe_create_buffer_from_file(filepath)
                    sdl.RaiseWindow(bragi.ctx.window)
                    delete(e.drop.file)
                }
                case .MOUSEBUTTONDOWN: {
                    bragi.cbuffer.cursor.region_enabled = false
                    m := e.button

                    if m.button == 1 {
                        pos := Vector2{ int(m.x), int(m.y) }

                        if m.clicks == 1 {
                            editor_position_cursor(pos)
                        } else {
                            editor_select(pos)
                        }
                    }
                }
                case .MOUSEWHEEL: {
                    m := e.wheel
                    // TODO: Maybe make scrolling offset configurable
                    buffer_scroll(int(m.y * -1) * 5)
                }
                case .KEYDOWN: {
                    bragi.cbuffer.cursor.region_enabled = false
                    handle_key_down(e.key.keysym)
                }
                case .TEXTINPUT: {
                    bragi.cbuffer.cursor.region_enabled = false
                    bragi.keybinds.last_keystroke = sdl.GetTicks()
                    input_char := cstring(raw_data(e.text.text[:]))
                    insert_at_point(get_buffer_from_current_pane(), string(input_char))
                    buffer_insert_at_point(cstring(raw_data(e.text.text[:])))
                }
            }
        }

        buffer_correct_viewport()

        // render_old_version()
        render_new_version()

        sdl.RenderPresent(bragi.ctx.renderer)

        free_all(context.temp_allocator)

        frame_end = sdl.GetTicks()
        duration = frame_end - frame_start

        if duration < dt_ms {
            sdl.Delay(dt_ms - duration)
        }
    }

    destroy_sdl()
    editor_close()

    if reset_tracking_allocator(&tracking_allocator) {
        os.exit(1)
    }

    mem.tracking_allocator_destroy(&tracking_allocator)
}

render_new_version :: proc() {
    dt_ms : u32 = 1000 / FPS

    sdl.SetRenderDrawColor(bragi.ctx.renderer, 1, 32, 39, 255)
    sdl.RenderClear(bragi.ctx.renderer)

    std_char_size := get_standard_character_size()

    for pane in bragi.panes {
        x, y: i32
        str := entire_buffer_to_string(pane.buffer)
        cursor_rendered := false

        for c, index in str {
            char := bragi.ctx.characters[c]

            if c == '\n' {
                x = 0
                y += 1
            }

            if !cursor_rendered && pane.buffer.cursor == index {
                cursor_rendered = true

                sdl.SetRenderDrawColor(bragi.ctx.renderer, 100, 216, 203, 255)
                cursor_rect := sdl.Rect{
                    x, y * i32(std_char_size.y),
                    i32(std_char_size.x), i32(std_char_size.y),
                }
                sdl.RenderFillRect(bragi.ctx.renderer, &cursor_rect)
                sdl.SetRenderDrawColor(bragi.ctx.renderer, 255, 255, 255, 255)
                sdl.SetTextureColorMod(char.texture, 1, 32, 39)
            }

            char.dest.x = x
            char.dest.y = y * char.dest.h
            sdl.RenderCopy(bragi.ctx.renderer, char.texture, nil, &char.dest)
            x += char.dest.w

            if cursor_rendered {
                sdl.SetTextureColorMod(char.texture, 255, 255, 255)
            }
        }
    }
}

render_old_version :: proc() {
    dt_ms : u32 = 1000 / FPS

    sdl.SetRenderDrawColor(bragi.ctx.renderer, 1, 32, 39, 255)
    sdl.RenderClear(bragi.ctx.renderer)

    buf := bragi.cbuffer
    cursor := &buf.cursor
    viewport := buf.viewport
    std_char_size := get_standard_character_size()
    cursor_rendered := false

    cursor.timer += dt_ms

    if bragi.keybinds.last_keystroke == sdl.GetTicks() {
        cursor.timer = 0
        cursor.hidden = false
    }

    if cursor.timer > 500 {
        cursor.timer = 0
        cursor.hidden = !cursor.hidden
    }

    // TODO: Should be rendering the code that went through the parser/lexer
    // instead of just the code from the lines, with exceptions (maybe)
    // This also should be improved to make sense
    for line, yidx in buf.lines {
        x_pos: i32

        for c, xidx in line {
            char := bragi.ctx.characters[c]
            cpos := cursor.position

            if !cursor.hidden && !cursor_rendered && yidx == cpos.y && xidx == cpos.x {
                cursor_rendered = true

                sdl.SetRenderDrawColor(bragi.ctx.renderer, 100, 216, 203, 255)
                cursor_rect := sdl.Rect{
                    i32(cpos.x * std_char_size.x - viewport.x * std_char_size.x),
                    i32(cpos.y * std_char_size.y - viewport.y * std_char_size.y),
                    i32(std_char_size.x), i32(std_char_size.y),
                }
                sdl.RenderFillRect(bragi.ctx.renderer, &cursor_rect)
                sdl.SetRenderDrawColor(bragi.ctx.renderer, 255, 255, 255, 255)
                sdl.SetTextureColorMod(char.texture, 1, 32, 39)
            }

            if cursor.region_enabled {
                region_start := cursor.region_start
                region_end := cursor.position

                if yidx >= region_start.y && yidx <= region_end.y &&
                    xidx >= region_start.x && xidx < region_end.x {
                        sdl.SetRenderDrawColor(bragi.ctx.renderer, 1, 52, 63, 255)
                        region_rect := sdl.Rect{
                            x_pos - i32(viewport.x) * char.dest.w,
                            i32(yidx - viewport.y) * char.dest.h,
                            char.dest.w, char.dest.h,
                        }
                        sdl.RenderFillRect(bragi.ctx.renderer, &region_rect)
                        sdl.SetRenderDrawColor(bragi.ctx.renderer, 255, 255, 255, 255)
                    }
            }

            char.dest.x = x_pos - i32(viewport.x) * char.dest.w
            char.dest.y = i32(yidx - viewport.y) * char.dest.h
            sdl.RenderCopy(bragi.ctx.renderer, char.texture, nil, &char.dest)
            x_pos += char.dest.w

            if cursor_rendered {
                sdl.SetTextureColorMod(char.texture, 255, 255, 255)
            }
        }
    }

    if !cursor.hidden && !cursor_rendered {
        cpos := cursor.position
        cursor_rendered = true

        sdl.SetRenderDrawColor(bragi.ctx.renderer, 100, 216, 203, 255)
        cursor_rect := sdl.Rect{
            i32(cpos.x * std_char_size.x - viewport.x * std_char_size.x),
            i32(cpos.y * std_char_size.y - viewport.y * std_char_size.y),
            i32(std_char_size.x), i32(std_char_size.y),
        }
        sdl.RenderFillRect(bragi.ctx.renderer, &cursor_rect)
        sdl.SetRenderDrawColor(bragi.ctx.renderer, 255, 255, 255, 255)
    }

    { // Render modeline
        sdl.SetRenderDrawColor(bragi.ctx.renderer, 0, 86, 98, 255)
        background_rect := sdl.Rect{
            0, i32(bragi.ctx.window_size.y - std_char_size.y),
            i32(bragi.ctx.window_size.x), i32(std_char_size.y),
        }
        sdl.RenderFillRect(bragi.ctx.renderer, &background_rect)

        sdl.SetRenderDrawColor(bragi.ctx.renderer, 255, 255, 255, 255)
        name_x: i32 = 10
        for c in bragi.cbuffer.name {
            char := bragi.ctx.characters[c]
            char.dest.x = name_x
            char.dest.y = i32(bragi.ctx.window_size.y) - char.dest.h
            sdl.RenderCopy(bragi.ctx.renderer, char.texture, nil, &char.dest)
            name_x += char.dest.w
        }
    }
}
