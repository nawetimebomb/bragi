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

    find_file,
    save_file,
    save_file_as,

    switch_buffer,
    kill_current_buffer,

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
    paste,
    paste_from_history,
}

map_keystroke_to_command :: proc(key: Key_Code, modifiers: Modifiers_Set) -> Command {
    key_combination := strings.builder_make(context.temp_allocator)

    if .Ctrl    in modifiers do strings.write_string(&key_combination, "Ctrl-")
    if .Command in modifiers do strings.write_string(&key_combination, "Command-")
    if .Alt     in modifiers do strings.write_string(&key_combination, "Alt-")
    if .Shift   in modifiers do strings.write_string(&key_combination, "Shift-")
    if .Super   in modifiers do strings.write_string(&key_combination, "Super-")

    strings.write_string(&key_combination, input_key_code_to_string(key))

    log.debug(strings.to_string(key_combination))

    log.fatalf("could not find command for key '{}' with modifiers '{}'", key, modifiers)
    return .noop
}
