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
    copy_line,
    paste,
    paste_from_history,
}

// NOTE(nawe) the string is the keys to press in <>. For example, in <Ctrl-c> it would be "Ctrl-c".
commands_map: map[string]Command

commands_init :: proc() {
    log.warn("setting default commands, this should be replaced for commands in settings.bragi")
    commands_map["Ctrl-Z"]       = .undo
    commands_map["Ctrl-Shift-Z"] = .redo

    commands_map["Ctrl-C"]       = .copy_region
    commands_map["Ctrl-Shift-C"] = .copy_line
    commands_map["Ctrl-X"]       = .cut_region
    commands_map["Ctrl-Shift-X"] = .cut_line
    commands_map["Ctrl-V"]       = .paste
    commands_map["Ctrl-Shift-V"] = .paste_from_history
}

commands_destroy :: proc() {
    delete(commands_map)
}

map_keystroke_to_command :: proc(key: Key_Code, modifiers: Modifiers_Set) -> Command {
    key_combination := strings.builder_make(context.temp_allocator)

    if .Ctrl    in modifiers do strings.write_string(&key_combination, "Ctrl-")
    if .Command in modifiers do strings.write_string(&key_combination, "Command-")
    if .Alt     in modifiers do strings.write_string(&key_combination, "Alt-")
    if .Shift   in modifiers do strings.write_string(&key_combination, "Shift-")
    if .Super   in modifiers do strings.write_string(&key_combination, "Super-")

    strings.write_string(&key_combination, input_key_code_to_string(key))

    cmd, ok := commands_map[strings.to_string(key_combination)]

    if ok do return cmd

    log.fatalf("could not find command for key combination '{}'", strings.to_string(key_combination))
    return .noop
}
