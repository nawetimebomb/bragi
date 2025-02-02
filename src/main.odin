package main

import     "base:runtime"
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

SETTINGS_DATA     :: #load("../res/config.bragi")
SETTINGS_FILENAME :: "config.bragi"

TITLE_TIMEOUT :: 1 * time.Second

Program_Context :: struct {
    profiling:      bool,
    spall_buf:      spall.Buffer,
    spall_ctx:      spall.Context,
    pane_texture:   ^sdl.Texture,
}

Bragi :: struct {
    buffers:         [dynamic]Buffer,
    panes:           [dynamic]Pane,
    ui_pane:         UI_Pane,
    focused_index:   int,

    ctx:             Program_Context,
    keybinds:        Keybinds,
    settings:        Settings,
}

MINIMUM_WINDOW_SIZE      :: 800
DEFAULT_BASE_WINDOW_SIZE :: 900

FONT_EDITOR  :: #load("../res/FiraCode-Retina.ttf")
FONT_UI      :: #load("../res/FiraCode-Retina.ttf")
FONT_UI_BOLD :: #load("../res/FiraCode-SemiBold.ttf")

NUM_GLYPHS :: 128

Glyph :: struct {
    rect: sdl.Rect,
}

Font :: struct {
    em_width:     i32,
    face:         ^ttf.Font,
    glyphs:       [NUM_GLYPHS]Glyph,
    line_height:  i32,
    name:         string,
    texture:      ^sdl.Texture,
    texture_size: i32,
    x_advance:    i32,
}

font_editor:  Font
font_ui:      Font
font_ui_bold: Font

DEFAULT_FONT_EDITOR_SIZE :: 14
DEFAULT_FONT_UI_SIZE     :: 15

// font base size is the one configured by the user, the other ones are derived
font_editor_size : i32 = DEFAULT_FONT_EDITOR_SIZE
font_ui_size     : i32 = DEFAULT_FONT_UI_SIZE

char_width:     i32
char_x_advance: i32
line_height:    i32

window_width: i32
window_height: i32
dpi_scale: f32
window_in_focus: bool

bragi_allocator:  runtime.Allocator
bragi_is_running: bool

delta_time: time.Duration

bragi: Bragi

renderer: ^sdl.Renderer
window:   ^sdl.Window

destroy_context :: proc() {
    log.debug("Destroying context")
    sdl.DestroyRenderer(renderer)
    sdl.DestroyWindow(window)
    ttf.Quit()
    sdl.Quit()
}

destroy_editor :: proc() {
    log.debug("Destroying editor")

    if bragi.settings.save_desktop_mode {
        // TODO: Save desktop configuration
    }

    ui_pane_destroy()

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

    window = sdl.CreateWindow(TITLE, sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED,
                              DEFAULT_BASE_WINDOW_SIZE, DEFAULT_BASE_WINDOW_SIZE,
                              {.SHOWN, .RESIZABLE, .ALLOW_HIGHDPI})
    assert(window != nil, "Cannot open window")

    renderer = sdl.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
    assert(renderer != nil, "Cannot create renderer")

    sdl.SetCursor(sdl.CreateSystemCursor(.IBEAM))

    bragi.ctx.pane_texture = sdl.CreateTexture(
        renderer, .RGBA8888, .TARGET,
        DEFAULT_BASE_WINDOW_SIZE, DEFAULT_BASE_WINDOW_SIZE,
    )

    bragi_is_running = true
}

initialize_editor :: proc() {
    log.debug("Initializing editor")

    bragi.buffers = make([dynamic]Buffer, 0, 10)
    bragi.panes   = make([dynamic]Pane, 0, 2)

    ui_pane_init()

    p := add(pane_init())
    p.buffer = add(buffer_init("*notes*", 0))
    bragi.focused_index = 0
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

initialize_profiling :: proc() {
    log.debug("Initializing profiling")
	bragi.ctx.spall_ctx = spall.context_create("profile.spall")
	buf := make([]u8, spall.BUFFER_DEFAULT_SIZE)
	bragi.ctx.spall_buf = spall.buffer_create(buf)
    bragi.ctx.profiling = true
}

destroy_profiling :: proc() {
    log.debug("Destroying profiling")
    buf := bragi.ctx.spall_buf.data
    spall.buffer_destroy(&bragi.ctx.spall_ctx, &bragi.ctx.spall_buf)
    delete(buf)
    spall.context_destroy(&bragi.ctx.spall_ctx)
    bragi.ctx.profiling = false
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

    bragi_allocator = context.allocator

    window_in_focus = true
    window_width = DEFAULT_BASE_WINDOW_SIZE
    window_height = DEFAULT_BASE_WINDOW_SIZE


    // TODO: this should happen after we initialize settings, because we want to
    // load the prefered user fonts

    initialize_context()

    platform_init_fonts()

    initialize_settings()
    initialize_editor()
    load_keybinds()

    last_update_time := time.tick_now()
    previous_frame_time := time.tick_now()

    for bragi_is_running {
        frame_start := sdl.GetPerformanceCounter()

        set_bg(bragi.settings.colorscheme_table[.background])
        sdl.RenderClear(renderer)

        ui_pane_begin()

        for &p in bragi.panes {
            pane_begin(&p)
        }

        update_input()

        for &p, index in bragi.panes {
            focused := bragi.focused_index == index
            render_pane(&p, index, focused)
            pane_end(&p, index)
        }

        render_ui_pane()
        ui_pane_end()

        sdl.RenderPresent(renderer)

        free_all(context.temp_allocator)

        delta_time = time.tick_lap_time(&previous_frame_time)

        if time.tick_diff(last_update_time, time.tick_now()) > TITLE_TIMEOUT {
            last_update_time = time.tick_now()
            reload_settings()

            window_title := fmt.ctprintf(
                "Bragi v{0} | frametime: {1} | memory: {2}kb",
                VERSION, delta_time,
                tracking_allocator.current_memory_allocated / 1024,
            )
            sdl.SetWindowTitle(window, window_title)
        }

        frame_end := sdl.GetPerformanceCounter()

        if !window_in_focus {
            FRAMETIME_LIMIT :: 100 // 10 FPS

            elapsed :=
                f32(frame_end - frame_start) / f32(sdl.GetPerformanceCounter()) * 1000
            sdl.Delay(u32(math.floor(FRAMETIME_LIMIT - elapsed)))
        }
    }

    platform_deinit_fonts()

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
