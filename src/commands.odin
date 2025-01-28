package main

import "core:log"
import "core:strings"

Command :: enum {
    noop,
    modifier,
    quit,

    find_file,
    kill_current_buffer,
    save_buffer,

    delete_this_pane,
    delete_other_panes,
    new_pane_to_the_right,
    other_pane,

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

do_command :: proc(cmd: Command, p: ^Pane, data: any) {
    switch cmd {
    case .noop:                    log.error("NOT IMPLEMENTED")
    case .modifier:                add_modifier(data.(string))
    case .quit:                    bragi.ctx.running = false

    case .find_file:               editor_find_file(p)
    case .kill_current_buffer:     kill_current_buffer(p)
    case .save_buffer:             save_buffer(p)

    case .delete_this_pane:        editor_close_panes(p, .CURRENT)
    case .delete_other_panes:      editor_close_panes(p, .OTHER)
    case .new_pane_to_the_right:   editor_new_pane(p)
    case .other_pane:              editor_other_pane(p)

    case .undo:                    editor_undo_redo(p, .UNDO)
    case .redo:                    editor_undo_redo(p, .REDO)

    case .newline:                 newline(p)

    case .kill_region:             log.error("NOT IMPLEMENTED")
    case .kill_line:               delete_to(p, .LINE_END)
    case .kill_ring_save:          log.error("NOT IMPLEMENTED")
    case .yank:                    yank(p, handle_paste)
    case .yank_from_history:       log.error("NOT IMPLEMENTED")

    case .mark_backward_char:      log.error("NOT IMPLEMENTED")
    case .mark_backward_word:      log.error("NOT IMPLEMENTED")
    case .mark_backward_paragraph: log.error("NOT IMPLEMENTED")
    case .mark_forward_char:       log.error("NOT IMPLEMENTED")
    case .mark_forward_word:       log.error("NOT IMPLEMENTED")
    case .mark_forward_paragraph:  log.error("NOT IMPLEMENTED")
    case .mark_rectangle:          log.error("NOT IMPLEMENTED")
    case .mark_set:                log.error("NOT IMPLEMENTED")
    case .mark_whole_buffer:       log.error("NOT IMPLEMENTED")

    case .delete_backward_char:    delete_to(p, .LEFT)
    case .delete_backward_word:    delete_to(p, .WORD_START)
    case .delete_forward_char:     delete_to(p, .RIGHT)
    case .delete_forward_word:     delete_to(p, .WORD_END)

    case .backward_char:           move_to(p, .LEFT)
    case .backward_word:           move_to(p, .WORD_START)
    case .backward_paragraph:      log.error("NOT IMPLEMENTED")
    case .forward_char:            move_to(p, .RIGHT)
    case .forward_word:            move_to(p, .WORD_END)
    case .forward_paragraph:       log.error("NOT IMPLEMENTED")

    case .next_line:               move_to(p, .DOWN)
    case .previous_line:           move_to(p, .UP)

    case .beginning_of_buffer:     move_to(p, .BUFFER_START)
    case .beginning_of_line:       move_to(p, .LINE_START)
    case .end_of_buffer:           move_to(p, .BUFFER_END)
    case .end_of_line:             move_to(p, .LINE_END)

    case .self_insert:             log.error("NOT IMPLEMENTED")
    }
}

add_modifier :: proc(input: string) {
    k := [2]string{input, "-"}
    s := strings.concatenate(k[:])
    append(&bragi.keybinds.modifiers, s)
}
