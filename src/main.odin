package main

import     "base:runtime"
import     "core:fmt"
import     "core:log"
import     "core:math"
import     "core:mem"
import     "core:os"
import     "core:strings"
import     "core:time"
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

TITLE_TIMEOUT :: 1 * time.Second

Settings :: struct {
    mm: map[Major_Mode]Major_Mode_Settings,

    cursor_blink_delay_in_seconds: f32,
    font_size:                     i32,
    remove_trailing_whitespaces:   bool,
    save_desktop_mode:             bool,
}

Character_Texture :: struct {
    texture: ^sdl.Texture,
    dest:    sdl.Rect,
}

Program_Context :: struct {
    delta_time:     time.Duration,
    undo_allocator: runtime.Allocator,
    font:           ^ttf.Font,
    characters:     map[rune]Character_Texture,
    running:        bool,
    renderer:       ^sdl.Renderer,
    window:         ^sdl.Window,
    window_size:    Vector2,
    window_focused: bool,
}

Bragi :: struct {
    buffers:      [dynamic]Text_Buffer,
    panes:        [dynamic]Pane,
    current_pane: ^Pane,
    last_pane:    ^Pane,

    ctx:          Program_Context,
    keybinds:     Keybinds,
    settings:     Settings,
}

bragi: Bragi

destroy_context :: proc() {
    log.debug("Destroying context")
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

destroy_editor :: proc() {
    log.debug("Destroying editor")

    if bragi.settings.save_desktop_mode {
        // TODO: Save desktop configuration
    }

    for &b in bragi.buffers {
        destroy_text_buffer(&b)
    }
    delete(bragi.buffers)
    delete(bragi.panes)
}

destroy_settings :: proc() {
    log.debug("Destroying settings")

    delete(bragi.settings.mm)
}

initialize_editor :: proc() {
    log.debug("Initializing editor")

    bragi.buffers = make([dynamic]Text_Buffer, 0, 10)
    bragi.panes   = make([dynamic]Pane, 0, 2)

    create_pane()

    // TODO: This is a debug only thing
    filepath := "C:/Code/bragi/demo/hello.odin"
    open_file(filepath)
}

initialize_context :: proc() {
    log.debug("Initializing context")

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


    src_data :=
        sdl.RWFromConstMem(raw_data(DEFAULT_FONT_DATA), i32(len(DEFAULT_FONT_DATA)))
    bragi.ctx.font = ttf.OpenFontRW(src_data, true, DEFAULT_FONT_SIZE)
    assert(bragi.ctx.font != nil, sdl.GetErrorString())

    set_characters_textures()

    bragi.ctx.running        = true
    bragi.ctx.undo_allocator = context.allocator
    bragi.ctx.window_size    = { DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT }
}

initialize_settings :: proc() {
    log.debug("Initializing settings")

    set_major_modes_settings()
}

// NOTE: This function should run every time the user changes the font
set_characters_textures :: proc() {
    COLOR_WHITE : sdl.Color : { 255, 255, 255, 255 }
    ascii := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~á"

    clear(&bragi.ctx.characters)
    log.debug("Generating new character textures")

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

    initialize_settings()
    initialize_editor()
    initialize_context()
    load_keybinds()

    last_update_time := time.tick_now()
    previous_frame_time := time.tick_now()

    for bragi.ctx.running {
        input_handled: bool
        e: sdl.Event

        frame_start := sdl.GetPerformanceCounter()

        for sdl.PollEvent(&e) {
            #partial switch e.type {
                case .QUIT: bragi.ctx.running = false
                case .WINDOWEVENT: {
                    w := e.window

                    if w.event == .FOCUS_LOST {
                        bragi.ctx.window_focused = false
                        bragi.last_pane    = bragi.current_pane
                        bragi.current_pane = nil
                    } else if w.event == .FOCUS_GAINED {
                        bragi.ctx.window_focused = true
                        bragi.current_pane = bragi.last_pane
                        bragi.last_pane    = bragi.current_pane
                    }

                    if w.event == .RESIZED && w.data1 != 0 && w.data2 != 0 {
                        bragi.ctx.window_size = {
                            int(e.window.data1),
                            int(e.window.data2),
                        }
                    }
                }
                case .DROPFILE: {
                    filepath := string(e.drop.file)
                    open_file(filepath)
                    sdl.RaiseWindow(bragi.ctx.window)
                    delete(e.drop.file)
                }
            }

            if bragi.current_pane != nil {
                #partial switch e.type {
                    case .MOUSEBUTTONDOWN: {

                    }
                    case .MOUSEWHEEL: {
                        m := e.wheel
                        // TODO: Maybe make scrolling offset configurable
                        // buffer_scroll(int(m.y * -1) * 5)
                    }
                    case .KEYDOWN: {
                        input_handled = handle_keydown(e.key.keysym, bragi.current_pane)
                    }
                    case .TEXTINPUT: {
                        if !input_handled {
                            pane := bragi.current_pane
                            input_char := cstring(raw_data(e.text.text[:]))
                            insert_at(pane.buffer, pane.buffer.cursor, string(input_char))
                        }
                    }
                }
            }
        }

        update_pane(bragi.current_pane)

        // Start rendering
        sdl.SetRenderDrawColor(bragi.ctx.renderer, 1, 32, 39, 255)
        sdl.RenderClear(bragi.ctx.renderer)

        for &pane in bragi.panes {
            focused := &pane == bragi.current_pane
            render_caret(&pane, focused)
            render_pane_contents(&pane, focused)
            render_modeline(&pane, focused)
        }

        render_message_minibuffer()

        sdl.RenderPresent(bragi.ctx.renderer)

        free_all(context.temp_allocator)

        bragi.ctx.delta_time = time.tick_lap_time(&previous_frame_time)

        if time.tick_diff(last_update_time, time.tick_now()) > TITLE_TIMEOUT {
            last_update_time = time.tick_now()
            flags := sdl.GetWindowFlags(bragi.ctx.window)

            window_title := fmt.ctprintf(
                "Bragi v{0} | frametime: {1} | memory: {2}kb",
                VERSION, bragi.ctx.delta_time,
                tracking_allocator.current_memory_allocated / 1024,
            )
            sdl.SetWindowTitle(bragi.ctx.window, window_title)
        }

        frame_end := sdl.GetPerformanceCounter()

        if !bragi.ctx.window_focused {
            FRAMETIME_LIMIT :: 50 // 20 FPS

            elapsed := f32(frame_end - frame_start) / f32(sdl.GetPerformanceCounter()) * 1000
            sdl.Delay(u32(math.floor(FRAMETIME_LIMIT - elapsed)))
        }
    }

    destroy_context()
    destroy_editor()
    destroy_settings()

    if reset_tracking_allocator(&tracking_allocator) {
        os.exit(1)
    }

    mem.tracking_allocator_destroy(&tracking_allocator)
}

render_caret :: proc(pane: ^Pane, focused: bool) {
    std_char_size := get_standard_character_size()
    caret := &pane.caret

    caret_rect := sdl.Rect{
        i32(caret.position.x * std_char_size.x),
        i32(caret.position.y * std_char_size.y),
        i32(std_char_size.x), i32(std_char_size.y),
    }

    sdl.SetRenderDrawColor(bragi.ctx.renderer, 100, 216, 203, 255)

    if !caret.hidden && focused {
        sdl.RenderFillRect(bragi.ctx.renderer, &caret_rect)
    } else if !focused {
        sdl.RenderDrawRect(bragi.ctx.renderer, &caret_rect)
    }

    sdl.SetRenderDrawColor(bragi.ctx.renderer, 255, 255, 255, 255)
}

render_pane_contents :: proc(pane: ^Pane, focused: bool) {
    x, y: i32
    str := entire_buffer_to_string(pane.buffer)
    std_char_size := get_standard_character_size()

    for c, char_index in str {
        char := bragi.ctx.characters[c]
        column := x * i32(std_char_size.x)
        row := y * i32(std_char_size.y)

        // TODO: here I should have the lexer figuring out what color this character is
        sdl.SetTextureColorMod(char.texture, 255, 255, 255)

        if focused {
            caret := &pane.caret

            if caret.region_enabled {
                start_region := min(pane.caret.region_begin, pane.buffer.cursor)
                end_region   := max(pane.caret.region_begin, pane.buffer.cursor)

                if start_region <= char_index && end_region > char_index {
                    sdl.SetRenderDrawColor(bragi.ctx.renderer, 1, 52, 63, 255)
                    region_rect := sdl.Rect{
                        column, row, i32(std_char_size.x), i32(std_char_size.y),
                    }
                    sdl.RenderFillRect(bragi.ctx.renderer, &region_rect)
                    sdl.SetRenderDrawColor(bragi.ctx.renderer, 255, 255, 255, 255)
                }
            }

            if !caret.hidden && pane.buffer.cursor == char_index {
                sdl.SetTextureColorMod(char.texture, 1, 32, 39)
            }
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
    MARGIN :: 20

    std_char_size := get_standard_character_size()
    lmodeline_format := fmt.tprintf(
        "{0} {1}  ({2}, {3})",
        get_buffer_status(pane.buffer),
        pane.buffer.name,
        pane.caret.position.x, pane.caret.position.y,
    )
    rmodeline_format := fmt.tprintf(
        "{0}", bragi.settings.mm[pane.buffer.major_mode].name,
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

    for c, index in lmodeline_format {
        char := bragi.ctx.characters[c]

        if focused {
            sdl.SetTextureColorMod(char.texture, 255, 255, 255)
        } else {
            sdl.SetTextureColorMod(char.texture, 132, 132, 132)
        }

        char.dest.x = MARGIN + char.dest.w * i32(index)
        char.dest.y = y
        sdl.RenderCopy(bragi.ctx.renderer, char.texture, nil, &char.dest)
    }

    rmdf_padding := i32(len(rmodeline_format) * std_char_size.x)
    for c, index in rmodeline_format {
        char := bragi.ctx.characters[c]

        if focused {
            sdl.SetTextureColorMod(char.texture, 255, 255, 255)
        } else {
            sdl.SetTextureColorMod(char.texture, 132, 132, 132)
        }

        char.dest.x =
            i32(bragi.ctx.window_size.x) - MARGIN - rmdf_padding + char.dest.w * i32(index)
        char.dest.y = y
        sdl.RenderCopy(bragi.ctx.renderer, char.texture, nil, &char.dest)
    }
}

render_message_minibuffer :: proc() {
    std_char_size := get_standard_character_size()
    y : i32 = auto_cast (bragi.ctx.window_size.y - std_char_size.y)

    sdl.SetRenderDrawColor(bragi.ctx.renderer, 1, 32, 39, 255)
    background_rect := sdl.Rect{
        0, y, i32(bragi.ctx.window_size.x), i32(std_char_size.y),
    }
    sdl.RenderFillRect(bragi.ctx.renderer, &background_rect)
}
