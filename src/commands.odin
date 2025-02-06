package main

import "core:log"
import "core:strings"

Command :: enum {
    modifier,

    increase_font_size,
    decrease_font_size,
    reset_font_size,

    quit_mode,

    find_file,
    switch_buffer,
    search_backward,
    search_forward,
    kill_current_buffer,
    save_buffer,

    delete_this_pane,
    delete_other_panes,
    new_pane_to_the_right,
    other_pane,

    undo,
    redo,

    ui_select,

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
    switch {
    case cmd == .modifier:
        command_add_modifier(data.(string))
    case cmd == .quit_mode:
        command_reset_modes(p)
    case !widget_pane.enabled && cmd == .ui_select:
        // TODO: I don't like that I have to do this... but this is how inputs are
        // being handled at the moment
        newline(p)
    case widget_pane.enabled:
        ui_do_command(cmd, p, data)
    case :
        editor_do_command(cmd, p, data)
    }
}

command_add_modifier :: proc(input: string) {
    k := [2]string{input, "-"}
    s := strings.concatenate(k[:])
    append(&bragi.keybinds.modifiers, s)
}

command_reset_modes :: proc(p: ^Pane) {
    widgets_hide()
}
