package main

import "base:runtime"

import "core:crypto"
import "core:log"
import "core:mem"
import "core:time"

NAME    :: "Bragi"
ID      :: "bragi.base"
AUTHOR  :: "Nahuel J. Sacchetti"
URL     :: "https://github.com/nawetimebomb/bragi"
VERSION :: "0.01"

Global_Mode :: union #no_nil {
    Global_Mode_Edit,
    Global_Mode_Find_File,
    Global_Mode_Search,
}

Global_Mode_Edit :: struct {}

Global_Mode_Find_File :: struct {}

Global_Mode_Search :: struct {}

DEFAULT_FONT_EDITOR_SIZE :: 20
DEFAULT_FONT_UI_SIZE     :: 20

FONT_EDITOR_NAME      :: "chivo-mono.ttf"
FONT_UI_NAME          :: "chivo-mono.ttf"
FONT_UI_BOLD_NAME     :: "chivo-mono-bold.ttf"

FONT_EDITOR  :: #load("../res/fonts/chivo-mono.ttf")
FONT_UI      :: FONT_EDITOR
FONT_UI_BOLD :: #load("../res/fonts/chivo-mono-bold.ttf")

// these font sizes are configured by the user, the rest are derived from these.
font_editor_size : i32 = DEFAULT_FONT_EDITOR_SIZE
font_ui_size     : i32 = DEFAULT_FONT_UI_SIZE

MINIMUM_WINDOW_SIZE :: 800
DEFAULT_WINDOW_SIZE :: 1080

window_height:   i32  = DEFAULT_WINDOW_SIZE
window_width:    i32  = DEFAULT_WINDOW_SIZE
window_in_focus: bool = true

mouse_x: i32
mouse_y: i32

frame_delta_time: time.Duration

DEFAULT_SETTINGS_DATA :: #load("../res/settings.bragi")
SETTINGS_FILENAME     :: "settings.bragi"

active_pane:  ^Pane
global_mode:  Global_Mode
open_buffers: [dynamic]^Buffer
open_panes:   [dynamic]^Pane

events_this_frame: [dynamic]Event
modifiers_queue:   [dynamic]string

bragi_allocator: runtime.Allocator
bragi_context:   runtime.Context
bragi_running:   bool

// TODO(nawe) this should probably be an arena allocator that will contain
// the editor settings and array of panes and buffers. The buffer content
// should be virtual alloc themselves on their own arena, but for now we're
// always running in debug, so we care more about the tracking allocator.
tracking_allocator: mem.Tracking_Allocator

main :: proc() {
    context.logger = log.create_console_logger()
    context.random_generator = crypto.random_generator()

    when ODIN_DEBUG {
        default_allocator := context.allocator
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
    }

    bragi_allocator = context.allocator

    platform_init()

    initialize_font_related_stuff()
    active_pane = pane_create()

    UPDATE_TIMEOUT :: 500 * time.Millisecond
    last_update_time := time.tick_now()
    previous_frame_time := time.tick_now()

    bragi_running = true

    for bragi_running {
        platform_update_events()

        profiling_start("parsing events")
        for &event in events_this_frame {
            switch v in event.variant {
            case Event_Keyboard:
                if v.key_pressed == .F2 {
                    if debug.profiling {
                        profiling_destroy()
                    } else {
                        profiling_init()
                    }
                    event.handled = true
                    continue
                }

                switch mode in global_mode {
                case Global_Mode_Edit:       event.handled = edit_mode_keyboard_event_handler(v)
                case Global_Mode_Find_File:  event.handled = false; unimplemented()
                case Global_Mode_Search:     event.handled = false; unimplemented()
                }
            case Event_Mouse:
            case Event_Quit:
                bragi_running = false
                event.handled = true
            case Event_Window:
                if v.resizing || v.moving {
                    // NOTE(nawe) The user hasn't finished moving or
                    // resizing the window yet, so we skip any kind of
                    // checks. Maybe is also good to just skip
                    // rendering this frame, though we would want to
                    // keep reading inputs.
                    event.handled = true
                    continue
                }

                should_resize_window_to_mininum := false
                window_in_focus = v.window_focused

                if window_width != v.window_width || window_height != v.window_height {
                    if v.window_width < MINIMUM_WINDOW_SIZE || v.window_height < MINIMUM_WINDOW_SIZE {
                        should_resize_window_to_mininum = true
                    }

                    window_width = v.window_width if v.window_width > MINIMUM_WINDOW_SIZE else MINIMUM_WINDOW_SIZE
                    window_height = v.window_height if v.window_height > MINIMUM_WINDOW_SIZE else MINIMUM_WINDOW_SIZE

                    if should_resize_window_to_mininum {
                        platform_resize_window(window_width, window_height)
                    }

                    log.debug("updating pane textures due to resizing")
                    update_all_pane_textures()
                }

                event.handled = true
            }
        }
        profiling_end()

        set_background(0, 0, 0)
        prepare_for_drawing()
        update_and_draw_panes()
        draw_frame()

        free_all(context.temp_allocator)
        frame_delta_time = time.tick_lap_time(&previous_frame_time)

        if time.tick_diff(last_update_time, time.tick_now()) > UPDATE_TIMEOUT {
            last_update_time = time.tick_now()

            when ODIN_DEBUG {
                platform_update_window_title()
            }
        }
    }

    input_destroy()
    fonts_destroy()

    active_pane = nil

    for pane   in open_panes   do pane_destroy(pane)
    for buffer in open_buffers do buffer_destroy(buffer)

    delete(open_buffers)
    delete(open_panes)

    platform_destroy()

    when ODIN_DEBUG {
        reset_tracking_allocator(&tracking_allocator)
        mem.tracking_allocator_destroy(&tracking_allocator)
    }
}
