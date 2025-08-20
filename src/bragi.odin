package main

import "base:runtime"

import "core:log"
import "core:mem"
import "core:os"
import "core:time"

NAME    :: "Bragi"
ID      :: "bragi.base"
AUTHOR  :: "Nahuel J. Sacchetti"
URL     :: "https://github.com/nawetimebomb/bragi"
VERSION :: "0.01"

FONT_EDITOR_NAME    :: "chivo-mono.ttf"
FONT_EDITOR_DATA    :: #load("../res/fonts/chivo-mono.ttf")
FONT_UI_NAME        :: "roboto-regular.ttf"
FONT_UI_DATA        :: #load("../res/fonts/roboto-regular.ttf")
FONT_UI_ITALIC_NAME :: "roboto-italic.ttf"
FONT_UI_ITALIC_DATA :: #load("../res/fonts/roboto-italic.ttf")
FONT_UI_BOLD_NAME   :: "roboto-semibold.ttf"
FONT_UI_BOLD_DATA   :: #load("../res/fonts/roboto-bold.ttf")

MINIMUM_WINDOW_SIZE :: 800
DEFAULT_WINDOW_SIZE :: 1080

window_height:   i32  = DEFAULT_WINDOW_SIZE
window_width:    i32  = DEFAULT_WINDOW_SIZE
window_in_focus: bool = true
dpi_scale:       f32  = 1.0

mouse_x: i32
mouse_y: i32

frame_delta_time: time.Duration

DEFAULT_SETTINGS_DATA :: #load("../res/settings.bragi")
SETTINGS_FILENAME     :: "settings.bragi"

settings_file: os.Handle
settings:      Settings
colorscheme:   map[Face_Color]Color

active_pane:   ^Pane
open_buffers:  [dynamic]^Buffer
open_panes:    [dynamic]^Pane
global_widget: Widget

base_working_dir:    string
commands_map:        map[string]Command
events_this_frame:   [dynamic]Event
last_keystroke:      time.Tick
modifiers_queue:     [dynamic]string

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

    settings_init()
    platform_init()
    commands_init()
    debug_init()

    initialize_font_related_stuff()

    widget_init()
    active_pane = pane_create()

    previous_frame_time := time.tick_now()

    bragi_running = true

    for bragi_running {
        platform_update_events()

        profiling_start("parsing events")

        // NOTE(nawe) text input events come with their singular key
        // pressed event as well. If the event was handled by the key
        // press, we need to ignore the text input.
        text_input_events_to_ignore_this_frame := 0

        for &event in events_this_frame {
            switch v in event.variant {
            case Event_Drop_File:
                found := false

                for buffer in open_buffers {
                    if buffer.filepath == v.filepath {
                        switch_to_buffer(active_pane, buffer)
                        found = true
                        break
                    }
                }

                if !found {
                    buffer := buffer_get_or_create_from_file(v.filepath, v.data)
                    switch_to_buffer(active_pane, buffer)
                }

                event.handled = true
            case Event_Keyboard:
                if v.is_text_input && text_input_events_to_ignore_this_frame > 0 {
                    text_input_events_to_ignore_this_frame -= 1
                    event.handled = true
                    continue
                }

                handled := false

                #partial switch v.key_code {
                    case .K_F2: {
                        if debug.profiling {
                            profiling_destroy()
                        } else {
                            profiling_init()
                        }
                        handled = true
                    }
                    case .K_F3: {
                        debug.show_debug_info = !debug.show_debug_info
                        handled = true
                    }
                    case .K_ESCAPE: {
                        quit_mode_command()
                        handled = true
                    }
                }

                switch {
                case global_widget.active && !handled:  handled = widget_keyboard_event_handler(v)
                case !global_widget.active && !handled: handled = edit_mode_keyboard_event_handler(v)
                }

                // NOTE(nawe) this event was already handled by the
                // key pressed event and so we skip the next related
                // text input. This is to allow bindings with
                // modifiers that also have regular alphanumeric or
                // symbol characters as key pressed, like in Emacs C-x-3.
                if !v.is_text_input && handled {
                    text_input_events_to_ignore_this_frame += 1
                }

                event.handled = handled
                last_keystroke = time.tick_now()
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

                    log.debug("updating necessary textures after resizing")
                    update_all_pane_textures()
                    update_widget_texture()
                }

                if v.dpi_scale != dpi_scale {
                    dpi_scale = v.dpi_scale
                    initialize_font_related_stuff()
                }

                event.handled = true
            }
        }
        profiling_end()

        set_color(.background)
        prepare_for_drawing()
        update_opened_buffers()
        update_active_pane()
        update_and_draw_panes()
        update_and_draw_widget()
        debug_draw()
        draw_frame()

        free_all(context.temp_allocator)
        frame_delta_time = time.tick_lap_time(&previous_frame_time)
    }

    widget_close()
    input_destroy()
    fonts_destroy()
    commands_destroy()
    debug_destroy()

    active_pane = nil

    for pane   in open_panes   do pane_destroy(pane)
    for buffer in open_buffers do buffer_destroy(buffer)

    delete(open_buffers)
    delete(open_panes)
    delete(colorscheme)
    delete(base_working_dir)

    platform_destroy()

    when ODIN_DEBUG {
        reset_tracking_allocator(&tracking_allocator)
        mem.tracking_allocator_destroy(&tracking_allocator)
    }
}
