package main

import "core:log"
import "core:prof/spall"

Debug :: struct {
    profiling:      bool,
    spall_buf:      spall.Buffer,
    spall_ctx:      spall.Context,
}

debug: Debug

profiling_init :: proc() {
    log.debug("Initializing profiling")
	debug.spall_ctx = spall.context_create("profile.spall")
	buf := make([]u8, spall.BUFFER_DEFAULT_SIZE)
	debug.spall_buf = spall.buffer_create(buf)
    debug.profiling = true
}

profiling_destroy :: proc() {
    log.debug("Destroying profiling")
    buf := debug.spall_buf.data
    spall.buffer_destroy(&debug.spall_ctx, &debug.spall_buf)
    delete(buf)
    spall.context_destroy(&debug.spall_ctx)
    debug.profiling = false
}


profiling_start :: proc(name: string, loc := #caller_location) {
    if !debug.profiling {
        return
    }

    spall._buffer_begin(&debug.spall_ctx, &debug.spall_buf, name, "", loc)
}

profiling_end :: proc() {
    if !debug.profiling {
        return
    }

    spall._buffer_end(&debug.spall_ctx, &debug.spall_buf)
}
