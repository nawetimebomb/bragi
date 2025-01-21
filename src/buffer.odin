package main

import "base:runtime"
import "core:os"
import "core:strings"
import "core:time"

UNDO_TIMEOUT :: 300 * time.Millisecond

History_State :: struct {
    cursor:    int,
    data:      []u8,
    dirty:     bool,
    gap_end:   int,
    gap_start: int,
}

Buffer :: struct {
    allocator:      runtime.Allocator,

    cursor:         int,
    data:           []u8,
    dirty:          bool,
    gap_end:        int,
    gap_start:      int,

    redo:           [dynamic]History_State,
    undo:           [dynamic]History_State,
    history_limit:  int,
    current_time:   time.Tick,
    last_edit_time: time.Tick,

    builder:        ^strings.Builder,

    filpath:        string,
    major_mode:     Major_Mode,
    name:           string,
    readonly:       bool,
}
