package main

import "core:prof/spall"

Debug :: struct {
    profiling:      bool,
    spall_buf:      spall.Buffer,
    spall_ctx:      spall.Context,
}

debug: Debug

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
