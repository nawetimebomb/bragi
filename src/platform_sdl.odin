package main

// TODO(nawe) hopefully I will get rid of SDL at some point, but since
// I use multiple systems, I need my editor to support all three major
// systems right of the bat and I don't have any idea on how Metal
// works. So in the meantime, I leverage all the power of SDL, but I
// want to make this from scratch instead.

import     "core:fmt"
import     "core:log"

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

platform_update_window_title :: proc() {
    window_title := fmt.ctprintf(
        "{} v{} | frametime: {} | memory: {}kb",
        NAME, VERSION, frame_delta_time,
        tracking_allocator.current_memory_allocated / 1024,
    )
    sdl.SetWindowTitle(window, window_title)
}

platform_update_events :: proc() {
    input_update_and_prepare()

    e: sdl.Event

    for sdl.PollEvent(&e) {
        #partial switch e.type {
            case .QUIT: input_register(Event_Quit{})
        }
    }
}

platform_resize_window :: proc(w, h: i32) {
    sdl.SetWindowSize(window, w, h)
}
