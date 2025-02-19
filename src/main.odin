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

TITLE   :: "Bragi"
VERSION :: "0b"

TITLE_TIMEOUT :: 1 * time.Second

Program_Context :: struct {
    profiling:      bool,
    spall_buf:      spall.Buffer,
    spall_ctx:      spall.Context,
}

Bragi :: struct {
    ctx:             Program_Context,
    keybinds:        Keybinds,
    settings:        Settings,
}

FONT_EDITOR  :: #load("../res/FiraCode-Retina.ttf")
FONT_UI      :: #load("../fonts/RobotoMono-Regular.ttf")
FONT_UI_BOLD :: #load("../fonts/RobotoMono-Bold.ttf")

font_editor:  Font
font_ui:      Font
font_ui_bold: Font

DEFAULT_FONT_EDITOR_SIZE :: 25
DEFAULT_FONT_UI_SIZE     :: 20

// font base size is the one configured by the user, the other ones are derived
font_editor_size : u32 = DEFAULT_FONT_EDITOR_SIZE
font_ui_size     : u32 = DEFAULT_FONT_UI_SIZE

// font_editor related values
char_width:             i32
line_height:            i32
xadvance:               i32
y_offset_for_centering: f32

MINIMUM_WINDOW_SIZE :: 1000
DEFAULT_WINDOW_SIZE :: 1000
DEFAULT_WINDOW_POS  :: sdl.WINDOWPOS_CENTERED

dpi_scale:       f32
renderer:        ^sdl.Renderer
window:          ^sdl.Window
window_x:        i32 = DEFAULT_WINDOW_POS
window_y:        i32 = DEFAULT_WINDOW_POS
window_width:    i32 = DEFAULT_WINDOW_SIZE
window_height:   i32 = DEFAULT_WINDOW_SIZE
window_in_focus: bool

mouse_x: i32
mouse_y: i32

bragi_is_running: bool
frame_delta_time: time.Duration
frame_counter: u64

open_buffers: [dynamic]Buffer
open_panes:   [dynamic]Pane
current_pane: ^Pane
widgets_pane: Widgets

SETTINGS_DATA     :: #load("../res/settings.bragi")
SETTINGS_FILENAME :: "settings.bragi"

colorscheme: map[Face]Color
keymaps: Keymaps
settings: Settings

bragi: Bragi

destroy_context :: proc() {
    log.debug("Destroying context")
    sdl.DestroyRenderer(renderer)
    sdl.DestroyWindow(window)
    sdl.Quit()
}

destroy_editor :: proc() {
    log.debug("Destroying editor")

    if bragi.settings.save_desktop_mode {
        // TODO: Save desktop configuration
    }

    widgets_destroy()

    for &b in open_buffers { buffer_destroy(&b) }
    for &p in open_panes   { pane_destroy(&p) }
    delete(open_buffers)
    delete(open_panes)
    delete(bragi.keybinds.modifiers)
}

destroy_settings :: proc() {
    log.debug("Destroying settings")

    delete(bragi.settings.major_modes_table)
    delete(colorscheme)

    for key, _ in bragi.settings.keybindings_table {
        delete(key)
    }
    delete(bragi.settings.keybindings_table)

        clear(&colorscheme)

    for key in keymaps.editor { delete(key) }
    for key in keymaps.global { delete(key) }
    for key in keymaps.widget { delete(key) }
    delete(keymaps.editor)
    delete(keymaps.global)
    delete(keymaps.widget)
}

initialize_context :: proc() {
    log.debug("Initializing context")

    assert(sdl.Init({.VIDEO}) == 0, sdl.GetErrorString())

    window = sdl.CreateWindow(TITLE, window_x, window_y, window_width, window_height,
                              {.SHOWN, .RESIZABLE, .ALLOW_HIGHDPI})
    assert(window != nil, "Cannot open window")

    renderer = sdl.CreateRenderer(window, -1, {.ACCELERATED})
    assert(renderer != nil, "Cannot create renderer")

    sdl.SetCursor(sdl.CreateSystemCursor(.IBEAM))

    sdl.GetWindowPosition(window, &window_x, &window_y)
    sdl.GetWindowSize(window, &window_width, &window_height)
    sdl.RaiseWindow(window)
    window_in_focus = true

    bragi_is_running = true
}

initialize_editor :: proc() {
    log.debug("Initializing editor")

    open_buffers = make([dynamic]Buffer, 0, 10)
    open_panes   = make([dynamic]Pane, 0, 2)

    widgets_init()
    current_pane = add(pane_create(add(buffer_init("*notes*", 0))))
    editor_open_file(current_pane, "C:/Code/bragi/demo/hello.odin")
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

    // TODO: this should happen after we initialize settings, because we want to
    // load the prefered user fonts
    fonts_init()

    initialize_settings()
    initialize_editor()
    load_keybinds()

    bragi.settings.show_line_numbers = true
    bragi.settings.line_wrap_by_default = true
    bragi.settings.show_trailing_whitespaces = true

    last_update_time := time.tick_now()
    previous_frame_time := time.tick_now()

    for bragi_is_running {
        frame_counter += 1
        frame_start := sdl.GetPerformanceCounter()

        set_bg(colorscheme[.background])
        sdl.RenderClear(renderer)

        process_inputs()
        widgets_update_draw()
        update_and_draw_active_pane()

        for &p in open_panes {
            if p.id != current_pane.id {
                update_and_draw_dormant_panes(&p)
            }
        }

        sdl.RenderPresent(renderer)

        free_all(context.temp_allocator)

        frame_delta_time = time.tick_lap_time(&previous_frame_time)

        if time.tick_diff(last_update_time, time.tick_now()) > TITLE_TIMEOUT {
            last_update_time = time.tick_now()
            reload_settings()

            window_title := fmt.ctprintf(
                "Bragi v{0} | frametime: {1} | memory: {2}kb",
                VERSION, frame_delta_time,
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
        } else {
            FRAMETIME_LIMIT :: 3.33 // 300 FPS

            elapsed :=
                f32(frame_end - frame_start) / f32(sdl.GetPerformanceCounter()) * 1000
            sdl.Delay(u32(math.floor(FRAMETIME_LIMIT - elapsed)))
        }
    }

    fonts_deinit()

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
