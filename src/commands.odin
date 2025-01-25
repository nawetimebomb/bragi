package main

import "core:log"
import "core:strings"

Command :: enum {
    noop,
    modifier,
    quit,

    find_file,

    undo,
    redo,

    newline,

    kill_region,       // cut selection
    kill_line,         // cut the rest of the line
    kill_ring_save,    // basically copy
    yank,              // just paste
    yank_from_history, // paste, but from a selection

    mark_backward_char,
    mark_backward_word,
    mark_backward_paragraph,
    mark_forward_char,
    mark_forward_word,
    mark_forward_paragraph,
    mark_rectangle,
    mark_set,
    mark_whole_buffer,

    delete_backward_char,
    delete_backward_word,
    delete_forward_char,
    delete_forward_word,

    backward_char,
    backward_word,
    backward_paragraph,
    forward_char,
    forward_word,
    forward_paragraph,

    next_line,
    previous_line,

    beginning_of_buffer,
    beginning_of_line,
    end_of_buffer,
    end_of_line,

    self_insert,
}

do_command :: proc(cmd: Command, b: ^Buffer, input: string) {
    switch cmd {
    case .noop: log.error("NOT IMPLEMENTED")
    case .modifier: add_modifier(input)
    case .quit: bragi.ctx.running = false

    case .find_file: log.error("NOT IMPLEMENTED")

    case .undo: log.error("NOT IMPLEMENTED")
    case .redo: log.error("NOT IMPLEMENTED")

    case .newline: log.error("NOT IMPLEMENTED")

    case .kill_region: log.error("NOT IMPLEMENTED")
    case .kill_line: log.error("NOT IMPLEMENTED")
    case .kill_ring_save: log.error("NOT IMPLEMENTED")
    case .yank: log.error("NOT IMPLEMENTED")
    case .yank_from_history: log.error("NOT IMPLEMENTED")

    case .mark_backward_char: log.error("NOT IMPLEMENTED")
    case .mark_backward_word: log.error("NOT IMPLEMENTED")
    case .mark_backward_paragraph: log.error("NOT IMPLEMENTED")
    case .mark_forward_char: log.error("NOT IMPLEMENTED")
    case .mark_forward_word: log.error("NOT IMPLEMENTED")
    case .mark_forward_paragraph: log.error("NOT IMPLEMENTED")
    case .mark_rectangle: log.error("NOT IMPLEMENTED")
    case .mark_set: log.error("NOT IMPLEMENTED")
    case .mark_whole_buffer: log.error("NOT IMPLEMENTED")

    case .delete_backward_char: log.error("NOT IMPLEMENTED")
    case .delete_backward_word: log.error("NOT IMPLEMENTED")
    case .delete_forward_char: log.error("NOT IMPLEMENTED")
    case .delete_forward_word: log.error("NOT IMPLEMENTED")

    case .backward_char: log.error("NOT IMPLEMENTED")
    case .backward_word: log.error("NOT IMPLEMENTED")
    case .backward_paragraph: log.error("NOT IMPLEMENTED")
    case .forward_char: log.error("NOT IMPLEMENTED")
    case .forward_word: log.error("NOT IMPLEMENTED")
    case .forward_paragraph: log.error("NOT IMPLEMENTED")

    case .next_line: move_cursor(b, .down)
    case .previous_line: log.error("NOT IMPLEMENTED")

    case .beginning_of_buffer: log.error("NOT IMPLEMENTED")
    case .beginning_of_line: log.error("NOT IMPLEMENTED")
    case .end_of_buffer: log.error("NOT IMPLEMENTED")
    case .end_of_line: log.error("NOT IMPLEMENTED")

    case .self_insert: log.error("NOT IMPLEMENTED")
    }
}

add_modifier :: proc(input: string) {
    k := [2]string{input, "-"}
    s := strings.concatenate(k[:], context.temp_allocator)
    append(&bragi.keybinds.modifiers, s)
}
