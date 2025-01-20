package main

import     "base:runtime"
import     "core:fmt"
import     "core:log"
import     "core:math"
import     "core:mem"
import     "core:os"
import     "core:slice"
import     "core:strings"
import     "core:time"
import     "core:unicode/utf8"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

TITLE   :: "Bragi"
VERSION :: 0

DEFAULT_FONT_DATA     :: #load("../res/font/firacode.ttf")
DEFAULT_FONT_SIZE     :: 24
DEFAULT_WINDOW_WIDTH  :: 1024
DEFAULT_WINDOW_HEIGHT :: 768

SETTINGS_DATA     :: #load("../res/config.bragi")
SETTINGS_FILENAME :: "config.bragi"

TITLE_TIMEOUT :: 1 * time.Second

Settings :: struct {
    handle:                      os.Handle,
    last_write_time:             os.File_Time,
    use_internal_data:           bool,

    major_modes_table:           Major_Modes_Table,
    colorscheme_table:           Colorscheme_Table,

    cursor_blink_timeout:        f32,
    font_size:                   u32,
    remove_trailing_whitespaces: bool,
    save_desktop_mode:           bool,
    show_line_numbers:           bool,
}

Character_Texture :: struct {
    dest:    sdl.Rect,
    texture: ^sdl.Texture,
}

Program_Context :: struct {
    delta_time:     time.Duration,
    undo_allocator: runtime.Allocator,
    font:           ^ttf.Font,
    characters:     map[rune]Character_Texture,
    running:        bool,
    renderer:       ^sdl.Renderer,
    window:         ^sdl.Window,
    window_size:    [2]i32,
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
    for &p in bragi.panes {
        delete(p.caret.highlights)
    }
    delete(bragi.panes)
}

destroy_settings :: proc() {
    log.debug("Destroying settings")

    delete(bragi.settings.major_modes_table)
    delete(bragi.settings.colorscheme_table)
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

initialize_editor :: proc() {
    log.debug("Initializing editor")

    bragi.buffers = make([dynamic]Text_Buffer, 0, 10)
    bragi.panes   = make([dynamic]Pane, 0, 2)

    create_pane()

    // TODO: This is a debug only thing
    filepath := "C:/Code/bragi/res/config.bragi"
    open_file(filepath)
}

initialize_settings :: proc() {
    log.debug("Initializing settings")

    if !os.exists(SETTINGS_FILENAME) || true {
        if os.write_entire_file_or_err(SETTINGS_FILENAME, SETTINGS_DATA) != nil {
            log.errorf("Fail to create settings file")
        }
    }

    if handle, err := os.open(SETTINGS_FILENAME); err == nil {
        if last_write_time, err := os.last_write_time(handle); err == nil {
            bragi.settings.handle = handle
            bragi.settings.last_write_time = last_write_time
            load_settings_from_file()
            return
        }
    }

    log.errorf("Fail to load settings from file")
    load_settings_from_internal_data()
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
            dest    = dest_rect,
            texture = texture,
        }

        sdl.FreeSurface(surface)
        delete(ostr)
    }
}

get_standard_character_size :: proc() -> [2]i32 {
    M_char_rect := bragi.ctx.characters['M'].dest
    return { M_char_rect.w, M_char_rect.h }
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
                    }

                    if w.event == .RESIZED && w.data1 != 0 && w.data2 != 0 {
                        bragi.ctx.window_size = {
                            e.window.data1, e.window.data2,
                        }
                    }
                }
                case .DROPFILE: {
                    sdl.RaiseWindow(bragi.ctx.window)
                    filepath := string(e.drop.file)
                    open_file(filepath)
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
        render()

        free_all(context.temp_allocator)

        bragi.ctx.delta_time = time.tick_lap_time(&previous_frame_time)

        if time.tick_diff(last_update_time, time.tick_now()) > TITLE_TIMEOUT {
            last_update_time = time.tick_now()
            reload_settings()

            window_title := fmt.ctprintf(
                "Bragi v{0} | frametime: {1} | memory: {2}kb",
                VERSION, bragi.ctx.delta_time,
                tracking_allocator.current_memory_allocated / 1024,
            )
            sdl.SetWindowTitle(bragi.ctx.window, window_title)        }

        frame_end := sdl.GetPerformanceCounter()

        if !bragi.ctx.window_focused {
            FRAMETIME_LIMIT :: 50 // 20 FPS

            elapsed :=
                f32(frame_end - frame_start) / f32(sdl.GetPerformanceCounter()) * 1000
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

render_pane_contents :: proc(pane: ^Pane, focused: bool) {
    x, y: i32
    str := entire_buffer_to_string(pane.buffer)
    std_char_size := get_standard_character_size()
    highlight_index := 0
    current_highlight := -1
    highlights_len := 0

    for c, char_index in str {
        char := bragi.ctx.characters[c]
        column := (x - pane.camera.x) * std_char_size.x
        row := (y - pane.camera.y) * std_char_size.y
        caret := &pane.caret

        // TODO: here I should have the lexer figuring out what color this character is
        sdl.SetTextureColorMod(char.texture, 255, 255, 255)

        if current_highlight == -1 {
            if len(caret.highlights) > highlight_index {
                current_highlight = caret.highlights[highlight_index]
                highlights_len = caret.highlights_len
                highlight_index += 1
            }
        } else {
            if current_highlight <= char_index && highlights_len > 0 {
                sdl.SetTextureColorMod(char.texture, 255, 152, 0)
                highlights_len -= 1

                if highlights_len == 0 {
                    current_highlight = -1
                }
            }
        }

        if focused {
            if caret.region_enabled {
                start_region := min(pane.caret.region_begin, pane.buffer.cursor)
                end_region   := max(pane.caret.region_begin, pane.buffer.cursor)

                if start_region <= char_index && end_region > char_index {
                    sdl.SetRenderDrawColor(bragi.ctx.renderer, 1, 52, 63, 255)
                    region_rect := sdl.Rect{
                        column, row, std_char_size.x, std_char_size.y,
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
