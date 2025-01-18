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
    delta_time   : f32,
    font         : ^ttf.Font,
    characters   : map[rune]Character_Texture,
    running      : bool,
    renderer     : ^sdl.Renderer,
    window       : ^sdl.Window,
    window_size  : Vector2,
}

Bragi :: struct {
    ctx          : SDL_Context,

    buffers      : [dynamic]Text_Buffer,
    panes        : [dynamic]Pane,
    focused_pane : int,
    keybinds     : Keybinds,

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
        sdl.CreateRenderer(bragi.ctx.window, -1, {.ACCELERATED, .PRESENTVSYNC})
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
    ascii := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~á"

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
            log.errorf("{0}: Leaked {1} bytes", value.location, value.size)
            err = true
        }

        mem.tracking_allocator_clear(a)
        return err
    }

    editor_start()
    initialize_sdl()
    create_textures_for_characters()
    load_keybinds()

    last_update := sdl.GetTicks()
    frame_update_timer : f32 = 10

    for bragi.ctx.running {
        e: sdl.Event

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
                    editor_open_file(filepath)
                    sdl.RaiseWindow(bragi.ctx.window)
                    delete(e.drop.file)
                }
                case .MOUSEBUTTONDOWN: {
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
                    // buffer_scroll(int(m.y * -1) * 5)
                }
                case .KEYDOWN: {
                    handle_key_down(e.key.keysym)
                }
                case .TEXTINPUT: {
                    if !bragi.keybinds.key_handled {
                        pane := get_focused_pane()
                        bragi.keybinds.last_keystroke = sdl.GetTicks()
                        input_char := cstring(raw_data(e.text.text[:]))
                        insert_at_point(pane.buffer, string(input_char))
                    }

                    bragi.keybinds.key_handled = false
                }
            }
        }

        current_update := sdl.GetTicks()
        bragi.ctx.delta_time = f32(current_update - last_update) / 1000
        last_update = current_update

        update_pane(get_focused_pane())

        // Start rendering
        sdl.SetRenderDrawColor(bragi.ctx.renderer, 1, 32, 39, 255)
        sdl.RenderClear(bragi.ctx.renderer)

        for &pane, index in bragi.panes {
            focused := bragi.focused_pane == index
            render_pane_contents(&pane, focused)
            render_modeline(&pane, focused)
        }

        sdl.RenderPresent(bragi.ctx.renderer)

        free_all(context.temp_allocator)

        frame_update_timer += bragi.ctx.delta_time

        if frame_update_timer > 0.5 {
            frame_update_timer = 0

            window_title := fmt.ctprintf(
                "Bragi - {0} fps {1} frametime",
                1 / bragi.ctx.delta_time,
                bragi.ctx.delta_time,
            )
            sdl.SetWindowTitle(bragi.ctx.window, window_title)
        }
    }

    destroy_sdl()
    editor_close()

    if reset_tracking_allocator(&tracking_allocator) {
        os.exit(1)
    }

    mem.tracking_allocator_destroy(&tracking_allocator)
}

render_pane_contents :: proc(pane: ^Pane, focused: bool) {
    x, y: i32
    str := entire_buffer_to_string(pane.buffer)
    std_char_size := get_standard_character_size()
    pane.caret.animated = focused

    if pane.caret.animated {
        pane.caret.timer += bragi.ctx.delta_time

        if bragi.keybinds.last_keystroke == sdl.GetTicks() {
            pane.caret.timer = 0
            pane.caret.hidden = false
        }

        if pane.caret.timer > CARET_BLINK_TIMER_DEFAULT {
            pane.caret.timer = 0
            pane.caret.hidden = !pane.caret.hidden
        }
    } else {
        pane.caret.hidden = false
    }

    for c, char_index in str {
        char := bragi.ctx.characters[c]
        column := x * i32(std_char_size.x)
        row := y * i32(std_char_size.y)

        sdl.SetTextureColorMod(char.texture, 255, 255, 255)

        if !pane.caret.hidden && pane.buffer.cursor == char_index {
            caret_rect := sdl.Rect{
                column, row,
                i32(std_char_size.x), i32(std_char_size.y),
            }

            sdl.SetRenderDrawColor(bragi.ctx.renderer, 100, 216, 203, 255)

            if pane.caret.animated {
                sdl.RenderFillRect(bragi.ctx.renderer, &caret_rect)
                sdl.SetTextureColorMod(char.texture, 1, 32, 39)
            } else {
                sdl.RenderDrawRect(bragi.ctx.renderer, &caret_rect)
            }

            sdl.SetRenderDrawColor(bragi.ctx.renderer, 255, 255, 255, 255)
        }

        char.dest.x = column
        char.dest.y = row
        sdl.RenderCopy(bragi.ctx.renderer, char.texture, nil, &char.dest)

        x += 1

        if c == '\n' {
            x = 0
            y += 1
        }
    }
}

render_modeline :: proc(pane: ^Pane, focused: bool) {
    std_char_size := get_standard_character_size()
    padding_minimum_size :: 20
    modeline_format := fmt.tprintf(
        "{0} {1}  ({2}, {3})",
        get_buffer_status(pane.buffer),
        pane.buffer.name,
        pane.caret.position.x, pane.caret.position.y,
    )
    y := i32(bragi.ctx.window_size.y - std_char_size.y * 2)
    background_rect := sdl.Rect{
        0, y, i32(bragi.ctx.window_size.x), i32(std_char_size.y),
    }

    if focused {
        sdl.SetRenderDrawColor(bragi.ctx.renderer, 0, 86, 98, 255)
    } else {
        sdl.SetRenderDrawColor(bragi.ctx.renderer, 0, 16, 23, 255)
    }

    sdl.RenderFillRect(bragi.ctx.renderer, &background_rect)

    if focused {
        sdl.SetRenderDrawColor(bragi.ctx.renderer, 0, 130, 149, 255)
        sdl.RenderDrawRect(bragi.ctx.renderer, &background_rect)
    }

    for c, index in modeline_format {
        char := bragi.ctx.characters[c]

        if focused {
            sdl.SetTextureColorMod(char.texture, 255, 255, 255)
        } else {
            sdl.SetTextureColorMod(char.texture, 132, 132, 132)
        }

        char.dest.x = padding_minimum_size + char.dest.w * i32(index)
        char.dest.y = y
        sdl.RenderCopy(bragi.ctx.renderer, char.texture, nil, &char.dest)
    }
}
