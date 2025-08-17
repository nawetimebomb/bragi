package main

import "core:log"
import "core:strings"

Command :: enum u32 {
    noop,     // nothing
    modifier, // register and save to modify the next command

    increase_font_size,
    decrease_font_size,
    reset_font_size,

    quit_mode, // resets all modes

    move_start,
    move_end,
    move_left,
    move_right,
    move_down,
    move_up,
    move_prev_word,
    move_next_word,
    move_prev_paragraph,
    move_next_paragraph,
    move_beginning_of_line,
    move_end_of_line,

    select_all,
    select_left,
    select_right,

    find_buffer,
    find_file,

    kill_current_buffer,
    save_buffer,
    save_buffer_as,

    search_backward,
    search_forward,

    delete_this_pane,
    delete_other_pane,
    new_pane_to_the_right,
    other_pane,

    undo,
    redo,

    cut_region,
    cut_line,
    copy_region,
    copy_line,
    paste,
    paste_from_history,
}

commands_init :: proc() {
    log.warn("setting default commands, this should be replaced for commands in settings.bragi")

    commands_map["Ctrl-X"]       = .modifier
    commands_map["Ctrl-X-2"]     = .new_pane_to_the_right
    commands_map["Ctrl-+"]       = .increase_font_size
    commands_map["Ctrl--"]       = .decrease_font_size
    commands_map["Ctrl-0"]       = .reset_font_size

    commands_map["Home"]         = .move_start
    commands_map["End"]          = .move_end
    commands_map["Left"]         = .move_left
    commands_map["Right"]        = .move_right
    commands_map["Down"]         = .move_down
    commands_map["Up"]           = .move_up
    commands_map["Ctrl-Left"]    = .move_prev_word
    commands_map["Ctrl-Right"]   = .move_next_word
    commands_map["Ctrl-Up"]      = .move_prev_paragraph
    commands_map["Ctrl-Down"]    = .move_next_paragraph
    commands_map["Ctrl-A"]       = .move_beginning_of_line
    commands_map["Ctrl-E"]       = .move_end_of_line

    commands_map["Ctrl-Shift-A"]       = .select_all
    commands_map["Shift-Left"]   = .select_left
    commands_map["Shift-Right"]  = .select_right

    commands_map["Alt-B"]       = .find_buffer
    commands_map["Alt-F"]       = .find_file

    commands_map["Ctrl-W"]       = .kill_current_buffer

    commands_map["Ctrl-3"]       = .new_pane_to_the_right

    commands_map["Ctrl-Z"]       = .undo
    commands_map["Ctrl-Shift-Z"] = .redo

    commands_map["Ctrl-C"]       = .copy_region
    commands_map["Ctrl-Shift-C"] = .copy_line
    // commands_map["Ctrl-X"]       = .cut_region
    // commands_map["Ctrl-Shift-X"] = .cut_line
    commands_map["Ctrl-V"]       = .paste
    commands_map["Ctrl-Shift-V"] = .paste_from_history
}

commands_destroy :: proc() {
    delete(commands_map)
    delete(modifiers_queue)
}

map_keystroke_to_command :: proc(key: Key_Code, modifiers: Modifiers_Set) -> Command {
    key_combo := strings.builder_make(context.temp_allocator)

    for len(modifiers_queue) > 0 {
        mod := pop(&modifiers_queue)
        strings.write_string(&key_combo, mod)
        delete(mod)
    }

    if .Ctrl    in modifiers do strings.write_string(&key_combo, "Ctrl-")
    if .Command in modifiers do strings.write_string(&key_combo, "Command-")
    if .Alt     in modifiers do strings.write_string(&key_combo, "Alt-")
    if .Shift   in modifiers do strings.write_string(&key_combo, "Shift-")
    if .Super   in modifiers do strings.write_string(&key_combo, "Super-")

    strings.write_string(&key_combo, input_key_code_to_string(key))

    cmd, ok := commands_map[strings.to_string(key_combo)]
    if ok {
        if cmd == .modifier {
            strings.write_string(&key_combo, "-")
            append(&modifiers_queue, strings.clone(strings.to_string(key_combo)))
            return .modifier
        } else {
            return cmd
        }
    }

    return .noop
}

quit_mode_command :: proc() {
    widget_close()
}
