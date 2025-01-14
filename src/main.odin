package main

import     "base:runtime"
import     "core:unicode/utf8"
import     "core:fmt"
import     "core:log"
import     "core:mem"
import     "core:os"
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

CharacterTexture :: struct {
    texture : ^sdl.Texture,
    dest    : sdl.Rect,
}

SDL_Context :: struct {
    font         : ^ttf.Font,
    characters   : map[rune]CharacterTexture,
    running      : bool,
    renderer     : ^sdl.Renderer,
    window       : ^sdl.Window,
    window_size  : Vector2,
}

Bragi :: struct {
    cbuffer  : ^Buffer,
    buffers  : [dynamic]Buffer,

    settings : Settings,
    ctx      : SDL_Context,
}

bragi: Bragi

initialize_sdl :: proc() {
    assert(sdl.Init({.VIDEO, .EVENTS}) == 0, sdl.GetErrorString())
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

        bragi.ctx.characters[c] = CharacterTexture{
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
                        editor_adjust_viewport()
                    }
                }
                case .DROPFILE: {
                    filepath := string(e.drop.file)
                    bragi.cbuffer = editor_maybe_create_buffer_from_file(filepath)
                    sdl.RaiseWindow(bragi.ctx.window)
                    delete(e.drop.file)
                }
                case .MOUSEBUTTONDOWN: {
                    m := e.button

                    if m.button == 1 &&  m.clicks == 1 {
                        editor_position_cursor({ int(m.x), int(m.y) })
                    }
                }
                case .MOUSEWHEEL: {
                    m := e.wheel
                    editor_scroll(int(m.y * -1))
                }
                case .KEYDOWN: {
                    #partial switch e.key.keysym.sym {
                        // TODO: Dev mode only
                        case .ESCAPE    : bragi.ctx.running = false
                        case .BACKSPACE : editor_delete_char_at_point(.Left)
                        case .DELETE    : editor_delete_char_at_point(.Right)
                        case .RETURN    : editor_insert_new_line_and_indent()
                        case .UP:
                            if e.key.keysym.mod == sdl.KMOD_LCTRL {
                                editor_move_cursor(.Page_Up)
                            } else {
                                editor_move_cursor(.Up)
                            }
                        case .DOWN: {
                            if e.key.keysym.mod == sdl.KMOD_LCTRL {
                                editor_move_cursor(.Page_Down)
                            } else {
                                editor_move_cursor(.Down)
                            }
                        }
                        case .LEFT: {
                            if e.key.keysym.mod == sdl.KMOD_LCTRL {
                                editor_move_cursor(.Begin_Line)
                            } else {
                                editor_move_cursor(.Left)
                            }
                        }
                        case .RIGHT: {
                            if e.key.keysym.mod == sdl.KMOD_LCTRL {
                                editor_move_cursor(.End_Line)
                            } else {
                                editor_move_cursor(.Right)
                            }
                        }
                        case .A, .E, .B, .F, .P, .N, .PERIOD: {
                            if e.key.keysym.mod == sdl.KMOD_LCTRL {
                                #partial switch e.key.keysym.sym {
                                    case .A       : editor_move_cursor(.Begin_Line)
                                    case .E       : editor_move_cursor(.End_Line)
                                    case .P       : editor_move_cursor(.Up)
                                    case .N       : editor_move_cursor(.Down)
                                    case .B       : editor_move_cursor(.Left)
                                    case .F       : editor_move_cursor(.Right)
                                    case .PERIOD  : editor_move_cursor(.End_File)
                                }
                            }
                        }
                     }
                }
                case .TEXTINPUT: {
                    editor_insert_at_point(cstring(raw_data(e.text.text[:])))
                }
            }
        }

        editor_adjust_viewport()

        sdl.SetRenderDrawColor(bragi.ctx.renderer, 1, 32, 39, 255)
        sdl.RenderClear(bragi.ctx.renderer)

        viewport := bragi.cbuffer.viewport

        // TODO: Should be rendering the code that went through the parser/lexer
        // instead of just the code from the lines, with exceptions (maybe)
        for line, index in bragi.cbuffer.lines {
            x: i32

            for c in line {
                char := bragi.ctx.characters[c]
                char.dest.x = x - i32(viewport.x) * char.dest.w
                char.dest.y = i32(index - viewport.y) * char.dest.h
                sdl.RenderCopy(bragi.ctx.renderer, char.texture, nil, &char.dest)
                x += char.dest.w
            }
        }

        std_char_size := get_standard_character_size()

        { // Render cursor
            sdl.SetRenderDrawColor(bragi.ctx.renderer, 255, 255, 255, 255)
            cursor_pos := bragi.cbuffer.cursor.position
            cursor_rect := sdl.Rect{
                i32(cursor_pos.x * std_char_size.x - viewport.x * std_char_size.x),
                i32(cursor_pos.y * std_char_size.y - viewport.y * std_char_size.y),
                2, i32(std_char_size.y),
            }

            sdl.RenderFillRect(bragi.ctx.renderer, &cursor_rect)
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
