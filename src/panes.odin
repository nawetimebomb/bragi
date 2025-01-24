package main

import "core:log"
import "core:strings"
import "core:time"

// @Description
// Panes follow the concept of "windows" in Emacs. The editor window can separate in
// different panes, and each pane can have its own functionality, or serve as a helper
// for the user to be able to work easily.

// Panes sometimes can contain reference to more than one buffer, because they are meant
// to do processing that require multiple buffers. For example, when doing a search, the
// pane will have a buffer so the user can enter the query, and have a secondary, readonly,
// buffer to show the results of the search. Input will also change in this type of panes
// so they can navigate up and down the results, but also being able to change the query.
// These "search" panes will also have a targeting pane, where the search will be executed,
// and the results will be pulled from.

// This enum will determine the functionality of the pane, and allow to change what the
// keybindings do.
Pane_Function :: enum {
    // The pane used for text input
    generic,
    // The pane used for selecting files
    find_file,
    // The pane that shows results and allows to search
    search,
}

_Pane :: struct {
    caret: struct {
        pos:            [2]i32,

        // The caret animation.
        blinking:       bool,
        blinking_times: int,
        last_keystroke: time.Tick,
        last_update:    time.Tick,
    },

    // Defines what the pane does.
    function: Pane_Function,

    // All panes will need some input. For the generic panes, this will be the file
    // contents or the code the user is entering. For the panes with results (I.e. search)
    // this will be where the user enters the query.
    input: struct {
        buf: ^Buffer,
        str: strings.Builder,
    },

    // Results buffer are usually readonly, and they are used to list results from
    // the input provided and the type of function that opened this pane.
    // `result.select` means the index of the current selection.
    result: struct {
        buf:    ^Buffer,
        str:    strings.Builder,
        select: int,
        // Some types of panes will need to act over other panes,
        // say opening a file, or searching through content.
        target: ^_Pane,
    },

    // Values that define the UI.
    show_scrollbar: bool,
    // The size of the pane, in relative positions (dimensions / size of character).
    relative_size:  [2]i32,
    // The size of the pane, in pixels.
    real_size:      [2]i32,
    // Where the pane starts, in reference to the whole window (from top-left).
    origin:         [2]i32,
    // The amount of scrolling the pane has done so far, depending of the caret.
    viewport:       [2]i32,
}

should_caret_reset_blink_timers :: #force_inline proc(p: ^_Pane) -> bool {
    CARET_RESET_TIMEOUT :: 50 * time.Millisecond
    time_diff := time.tick_diff(p.caret.last_keystroke, time.tick_now())
    return time_diff < CARET_RESET_TIMEOUT
}

should_caret_blink :: #force_inline proc(p: ^_Pane) -> bool {
    CARET_BLINK_COUNT   :: 20
    CARET_BLINK_TIMEOUT :: 500 * time.Millisecond
    time_diff := time.tick_diff(p.caret.last_update, time.tick_now())
    return p.caret.blinking_times < CARET_BLINK_COUNT && time_diff > CARET_BLINK_TIMEOUT
}

find_pane_in_window_coords :: proc(x, y: i32) -> ^_Pane {
    for &p in bragi._panes {
        origin := p.origin
        size := p.real_size

        if origin.x <= x && size.x > x && origin.y <= y && size.y > y {
            return &p
        }
    }

    log.errorf("Couldn't find a valid pane in coords [{0}, {1}]", x, y)
    return nil
}

// TODO: I need to figure out how the pane will be created.
// If the user tries to open a pane on the side, it should recalculate the horizontal
// size of the existing panes.
// TODO: Pane Function should set some defaults here.
pane_init :: proc(should_focus := true, func: Pane_Function = .generic) {
    p := _Pane{
        input = {
            str = strings.builder_make(),
        },
        result = {
            str = strings.builder_make(),
        },
    }

    append(&bragi._panes, p)

    if should_focus {
        bragi.focused_pane = &bragi._panes[len(bragi._panes) - 1]
    }
}

pane_begin :: proc(p: ^_Pane) {
    char_width, line_height := get_standard_character_size()

    if p.input.buf  != nil { buffer_begin(p.input.buf,  &p.input.str) }
    if p.result.buf != nil { buffer_begin(p.result.buf, &p.result.str) }

    p.relative_size.x = p.real_size.x / char_width
    p.relative_size.y = p.real_size.y / line_height

    if should_caret_reset_blink_timers(p) {
        p.caret.last_update = time.tick_now()
        p.caret.blinking = false
        p.caret.blinking_times = 0
    }

    if should_caret_blink(p) {
        p.caret.last_update = time.tick_now()
        p.caret.blinking = !p.caret.blinking
        p.caret.blinking_times += 1
    }

    p.caret.pos.y = i32(get_line_number(p.input.buf, p.input.buf.cursor))
    p.caret.pos.x = i32(p.input.buf.cursor - p.input.buf.lines[p.caret.pos.y])

    if p.caret.pos.x > p.viewport.x + p.relative_size.x {
        p.viewport.x = p.caret.pos.x - p.relative_size.x
    } else if p.caret.pos.x < p.viewport.x {
        p.viewport.x = p.caret.pos.x
    }

    if p.caret.pos.y > p.viewport.y + p.relative_size.y {
        p.viewport.y = p.caret.pos.y - p.relative_size.y
    } else if p.caret.pos.y < p.viewport.y {
        p.viewport.y = p.caret.pos.y
    }
}

pane_end :: proc(p: ^_Pane) {
    if p.input.buf  != nil { buffer_end(p.input.buf) }
    if p.result.buf != nil { buffer_end(p.result.buf) }
}

pane_destroy :: proc(p: ^_Pane) {
    p.input.buf = nil
    p.result.buf = nil
    strings.builder_destroy(&p.input.str)
    strings.builder_destroy(&p.result.str)
}
