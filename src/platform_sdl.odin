package main

// TODO(nawe) hopefully I will get rid of SDL at some point, but since
// I use multiple systems, I need my editor to support all three major
// systems right of the bat and I don't have any idea on how Metal
// works. So in the meantime, I leverage all the power of SDL, but I
// want to make this from scratch instead.

import     "core:log"
import     "core:os"
import     "core:reflect"
import     "core:strings"

import sdl "vendor:sdl3"

window: ^sdl.Window
renderer: ^sdl.Renderer

platform_init :: proc() {
    WINDOW_FLAGS  :: sdl.WindowFlags{.RESIZABLE, .HIGH_PIXEL_DENSITY}

    METADATA :: []struct{key, value: cstring}{
        {key = sdl.PROP_APP_METADATA_NAME_STRING,       value = NAME},
        {key = sdl.PROP_APP_METADATA_VERSION_STRING,    value = VERSION},
        {key = sdl.PROP_APP_METADATA_IDENTIFIER_STRING, value = ID},
        {key = sdl.PROP_APP_METADATA_CREATOR_STRING,    value = AUTHOR},
        {key = sdl.PROP_APP_METADATA_COPYRIGHT_STRING,  value = AUTHOR},
        {key = sdl.PROP_APP_METADATA_URL_STRING,        value = URL},
    }

    for item in METADATA {
        ok := sdl.SetAppMetadataProperty(item.key, item.value)
        if !ok {
            log.errorf("failed to set metadata for '{}'", item.key)
        }
    }

    when ODIN_DEBUG {
        sdl.SetLogPriorities(.ERROR)
        sdl.SetLogOutputFunction(platform_sdl_debug_log, nil)
    }

    log.debug("initializing SDL")

    if !sdl.Init({.VIDEO}) {
        log.fatal("failed to init SDL", sdl.GetError())
    }

    window = sdl.CreateWindow(NAME, window_width, window_height, WINDOW_FLAGS)
    if window == nil {
        log.fatal("failed to open window", sdl.GetError())
    }
    log.debugf("window created with driver '{}'", sdl.GetCurrentVideoDriver())

    renderer = sdl.CreateRenderer(window, nil)
    if renderer == nil {
        log.fatal("failed to setup renderer", sdl.GetError())
    }
    log.debugf("renderer created with driver '{}'", sdl.GetRenderDriver(0))

    sdl.SetRenderVSync(renderer, sdl.RENDERER_VSYNC_ADAPTIVE)

    if !sdl.StartTextInput(window) {
        log.fatal("cannot capture user input", sdl.GetError())
    }

    sdl.SetWindowMinimumSize(window, MINIMUM_WINDOW_SIZE, MINIMUM_WINDOW_SIZE)
    sdl.RaiseWindow(window)

    if settings.maximize_window_on_start {
        sdl.MaximizeWindow(window)
    }

    base_width, base_height: i32
    sdl.GetWindowSize(window, &base_width, &base_height)
    sdl.GetWindowSizeInPixels(window, &window_width, &window_height)

    if base_width == window_width && base_height == window_height {
        dpi_scale = 1.0
    } else {
        dpi_scale = min(
            f32(window_width) / f32(base_width),
            f32(window_height) / f32(base_height),
        )
    }
}

platform_destroy :: proc() {
    log.debug("deinitializing SDL")
    sdl.DestroyRenderer(renderer)
    sdl.DestroyWindow(window)
    sdl.Quit()
}

@(private="file")
platform_sdl_debug_log :: proc "c" (
    userdata: rawptr, category: sdl.LogCategory,
    priority: sdl.LogPriority, message: cstring,
) {
    context = bragi_context
    log.errorf("SDL {} [{}]: {}", category, priority, message)
}

platform_update_events :: proc() {
    profiling_start("capture platform events")
    input_update_and_prepare()

    event: sdl.Event
    for sdl.PollEvent(&event) {
        #partial switch event.type {
            case .QUIT: input_register(Event_Quit{})
            case .DROP_FILE: {
                filepath := string(event.drop.data)
                data, success := os.read_entire_file(filepath)
                if !success {
                    log.errorf("failed to open file '{}'", filepath)
                    continue
                }

                input_register(Event_Drop_File{
                    filepath = strings.clone(filepath),
                    data = data,
                })
            }
            case .WINDOW_FOCUS_GAINED, .WINDOW_FOCUS_LOST, .WINDOW_MOVED, .WINDOW_RESIZED: {
                // NOTE(nawe) Performance: it might be just better to
                // keep these resizes in a different list of events so
                // they can all be handled once the resizing is
                // done. The way to do it would be to register every
                // resize, once we get a list of not resizing on a
                // frame, we would process the last resizing.
                wevent := Event_Window{}
                base_width, base_height: i32
                sdl.GetWindowSize(window, &base_width, &base_height)
                sdl.GetWindowSizeInPixels(window, &wevent.window_width, &wevent.window_height)
                wevent.window_focused = event.type != .WINDOW_FOCUS_LOST

                if base_width == wevent.window_width && base_height == wevent.window_height {
                    wevent.dpi_scale = 1.0
                } else {
                    wevent.dpi_scale = min(
                        f32(wevent.window_width) / f32(base_width),
                        f32(wevent.window_height) / f32(base_height),
                    )
                }


                input_register(wevent)
            }
            case .KEY_DOWN: {
                key_code := Key_Code(event.key.scancode)

                if reflect.enum_value_has_name(key_code) {
                    // NOTE(nawe) we only want to register the
                    // following keys below if they are pressed
                    // together with a modifier key, the rest of the
                    // keys that are not below will always be
                    // registered.
                    last_alphanumeric_key: Key_Code = .Num_0
                    first_symbol_key, last_symbol_key: Key_Code = .Spacebar, .Slash
                    should_register := key_code > last_alphanumeric_key &&
                        key_code < first_symbol_key || key_code > last_symbol_key
                    mods := event.key.mod

                    // maybe alphanumeric or symbol, check for modifier key or leave
                    if !should_register && mods - sdl.KMOD_SHIFT - sdl.KMOD_MODE == {} do continue

                    kb_event := Event_Keyboard{}
                    kb_event.key_pressed = key_code
                    kb_event.repeat = event.key.repeat

                    if .LCTRL  in mods  || .RCTRL  in mods  do kb_event.modifiers += {.Ctrl}
                    if .LALT   in mods  || .RALT   in mods  do kb_event.modifiers += {.Alt}
                    if .LGUI   in mods  || .RGUI   in mods  do kb_event.modifiers += {.Super}
                    if .LSHIFT in mods  || .RSHIFT in mods  do kb_event.modifiers += {.Shift}

                    input_register(kb_event)
                }
            }
            case .TEXT_INPUT: input_register(Event_Keyboard{
                is_text_input = true,
                text = string(event.text.text),
            })
        }
    }
    profiling_end()
}

platform_resize_window :: #force_inline proc(w, h: i32) {
    sdl.SetWindowSize(window, w, h)
}
