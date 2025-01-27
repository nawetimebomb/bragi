package main

import     "base:runtime"
import     "core:crypto"
import     "core:encoding/uuid"
import     "core:fmt"
import     "core:log"
import     "core:math"
import     "core:mem"
import     "core:os"
import     "core:prof/spall"
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

Character_Texture :: struct {
    dest:    sdl.Rect,
    texture: ^sdl.Texture,
}

Program_Context :: struct {
    delta_time:     time.Duration,
    undo_allocator: runtime.Allocator,
    font:           ^ttf.Font,
    characters:     map[rune]Character_Texture,
    profiling:      bool,
    spall_buf:      spall.Buffer,
    spall_ctx:      spall.Context,
    running:        bool,
    pane_texture:   ^sdl.Texture,
    renderer:       ^sdl.Renderer,
    window:         ^sdl.Window,
    window_size:    [2]i32,
    window_focused: bool,
}

Bragi :: struct {
    buffers:         [dynamic]Buffer,
    panes:           [dynamic]Pane,
    focused_pane_id: uuid.Identifier,

    ctx:             Program_Context,
    keybinds:        Keybinds,
    settings:        Settings,
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

    for &p in bragi.panes {
        pane_destroy(&p)
    }
    for &b in bragi.buffers {
        buffer_destroy(&b)
    }
    delete(bragi.buffers)
    delete(bragi.panes)
    delete(bragi.keybinds.modifiers)
}

destroy_settings :: proc() {
    log.debug("Destroying settings")

    delete(bragi.settings.major_modes_table)
    delete(bragi.settings.colorscheme_table)

    for key, _ in bragi.settings.keybindings_table {
        delete(key)
    }
    delete(bragi.settings.keybindings_table)
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

    sdl.SetCursor(sdl.CreateSystemCursor(.IBEAM))

    bragi.ctx.pane_texture = sdl.CreateTexture(
        bragi.ctx.renderer, .RGBA8888, .TARGET,
        DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT,
    )

    bragi.ctx.running        = true
    bragi.ctx.undo_allocator = context.allocator
    bragi.ctx.window_size    = { DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT }
}

initialize_editor :: proc() {
    log.debug("Initializing editor")

    bragi.buffers = make([dynamic]Buffer, 0, 10)
    bragi.panes   = make([dynamic]Pane, 0, 2)

    p := add(pane_init())
    p.buffer = add(buffer_init("*notes*", 0))
    bragi.focused_pane_id = p.uid

    //    TODO: This is a debug only thing
    filepath := "C:/Code/bragi/demo/hello.odin"
    open_file(p, filepath)
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
    ascii := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~áéíóúÁÉÍÓÚ"

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

initialize_profiling :: proc() {
	bragi.ctx.spall_ctx = spall.context_create("profile.spall")
	buf := make([]u8, spall.BUFFER_DEFAULT_SIZE)
	bragi.ctx.spall_buf = spall.buffer_create(buf)
    bragi.ctx.profiling = true
}

destroy_profiling :: proc() {
    buf := bragi.ctx.spall_buf.data
    spall.buffer_destroy(&bragi.ctx.spall_ctx, &bragi.ctx.spall_buf)
    delete(buf)
    spall.context_destroy(&bragi.ctx.spall_ctx)
    bragi.ctx.profiling = false
}

main :: proc() {
    context.logger = log.create_console_logger()
    context.random_generator = crypto.random_generator()

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

    initialize_context()
    initialize_settings()
    initialize_editor()
    //initialize_profiling()
    load_keybinds()

    last_update_time := time.tick_now()
    previous_frame_time := time.tick_now()

    for bragi.ctx.running {
        frame_start := sdl.GetPerformanceCounter()

        for &p, index in bragi.panes {
            focused := bragi.focused_pane_id == p.uid
            pane_begin(&p)
            if focused { update_input(&p) }
            render_pane(&p, index, focused)
            pane_end(&p, index)
        }

        sdl.RenderPresent(bragi.ctx.renderer)

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
            sdl.SetWindowTitle(bragi.ctx.window, window_title)
        }

        frame_end := sdl.GetPerformanceCounter()

        if !bragi.ctx.window_focused {
            FRAMETIME_LIMIT :: 100 // 10 FPS

            elapsed :=
                f32(frame_end - frame_start) / f32(sdl.GetPerformanceCounter()) * 1000
            sdl.Delay(u32(math.floor(FRAMETIME_LIMIT - elapsed)))
        }
    }

    //destroy_profiling()
    destroy_editor()
    destroy_settings()
    destroy_context()

    reset_tracking_allocator(&tracking_allocator)
    mem.tracking_allocator_destroy(&tracking_allocator)
}

profiling_start :: proc(name: string, loc := #caller_location) {
    if !bragi.ctx.profiling {
        return
    }

    spall._buffer_begin(&bragi.ctx.spall_ctx, &bragi.ctx.spall_buf, name, "", loc)
}

profiling_end :: proc() {
    if !bragi.ctx.profiling {
        return
    }

    spall._buffer_end(&bragi.ctx.spall_ctx, &bragi.ctx.spall_buf)
}
