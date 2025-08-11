#+private file
package main

import "core:fmt"
import "core:log"
import "core:reflect"
import "core:slice"
import "core:strings"

SUBSECTION_WRONG_SECTION :: "Line {0}: Subsection {1} inside wrong section {2}"
MISSING_HEADING :: "Line {0}: Missing section heading"
MISSING_SUBHEADING :: "Line {0}: Missing subsection heading"
INVALID_SUBHEADING :: "Line {0}: Invalid subsection heading"
INCORRECT_FORMAT :: "Line {0}: Incorrect format. Expected: {1}, Got: {2}"
UNKNOWN_COMMAND :: "Line {0}: Unknown command {1}"
UNKNOWN_FACE :: "Line {0}: Unknown face {1}"

SECTION_SETTINGS  :: "[[settings]]"
SECTION_KEYMAPS   :: "[[keymaps]]"
SECTION_INTERFACE :: "[[interface]]"

SUBSECTION_UI          :: "[ui]"
SUBSECTION_COLORSCHEME :: "[colorscheme]"
SUBSECTION_GLOBAL      :: "[global]"
SUBSECTION_EDITOR      :: "[editor]"
SUBSECTION_WIDGET      :: "[widget]"

Command_Group :: union { Global_Command, Editor_Command, Widget_Command }

Section :: enum u8 {
    unspecified, interface, keymaps, settings,
}

Subsection :: enum u8 {
    unspecified, colorscheme, ui, editor, global, widget,
}

Settings_Parser :: struct {
    line:       int,
    offset:     int,
    section:    Section,
    subsection: Subsection,
}

p: Settings_Parser

@private
parse_settings_data :: proc(data: []u8) -> (success: bool) {
    is_not_empty :: proc(s: string) -> bool { return len(s) > 0 }


    clear(&colorscheme)

    for key in keymaps.editor { delete(key) }
    for key in keymaps.global { delete(key) }
    for key in keymaps.widget { delete(key) }
    for key in bragi.settings.keybindings_table { delete(key) }
    clear(&keymaps.editor)
    clear(&keymaps.global)
    clear(&keymaps.widget)
    clear(&bragi.settings.keybindings_table)

    settings_str := string(data)

    for line in strings.split_lines_iterator(&settings_str) {
        p.line += 1

        switch {
        case strings.starts_with(line, "#"): continue
        case line == SECTION_SETTINGS:
            p.section = .settings
            p.subsection = .unspecified
        case line == SECTION_KEYMAPS:
            p.section = .keymaps
            p.subsection = .unspecified
        case line == SECTION_INTERFACE:
            p.section = .interface
            p.subsection = .unspecified

        case line == SUBSECTION_COLORSCHEME:
            p.subsection = .colorscheme
            if p.section != .interface {
                log.errorf(SUBSECTION_WRONG_SECTION, p.line, line, p.section)
                return false
            }
        case line == SUBSECTION_UI:
            p.subsection = .ui
            if p.section != .interface {
                log.errorf(SUBSECTION_WRONG_SECTION, p.line, line, p.section)
                return false
            }

        case line == SUBSECTION_GLOBAL:
            p.subsection = .global
            if p.section != .keymaps {
                log.errorf(SUBSECTION_WRONG_SECTION, p.line, line, p.section)
                return false
            }
        case line == SUBSECTION_EDITOR:
            p.subsection = .editor
            if p.section != .keymaps {
                log.errorf(SUBSECTION_WRONG_SECTION, p.line, line, p.section)
                return false
            }
        case line == SUBSECTION_WIDGET:
            p.subsection = .widget
            if p.section != .keymaps {
                log.errorf(SUBSECTION_WRONG_SECTION, p.line, line, p.section)
                return false
            }

        case :
            sl := strings.split(line, " ", context.temp_allocator)
            setting := slice.filter(sl, is_not_empty, context.temp_allocator)
            if len(setting) == 0 { continue }

            switch p.section {
            case .unspecified:
                log.errorf(MISSING_HEADING, p.line)
                return false

            case .settings:
                if p.subsection != .unspecified {
                    log.errorf(INVALID_SUBHEADING, p.line)
                    return false
                }

                if len(setting) != 2 {
                    log.errorf(INCORRECT_FORMAT, p.line, "setting value", line)
                    continue
                }

                // TODO: Handle setting parsing

            case .keymaps:
                if p.subsection == .unspecified {
                    log.errorf(MISSING_SUBHEADING, p.line)
                    return false
                }

                if len(setting) < 2 {
                    log.errorf(INCORRECT_FORMAT, p.line, "command <keybinding>", line)
                    continue
                }

                switch p.subsection {
                case .unspecified, .ui, .colorscheme:
                    log.errorf(INVALID_SUBHEADING, p.line)
                    return false
                case .global:
                    command, ok := reflect.enum_from_name(Global_Command, setting[0])

                    if !ok {
                        log.errorf(UNKNOWN_COMMAND, p.line, setting[0])
                        continue
                    }

                    parse_command_keybind(command, setting[:], p.line)
                case .editor:
                    command, ok := reflect.enum_from_name(Editor_Command, setting[0])

                    if !ok {
                        log.errorf(UNKNOWN_COMMAND, p.line, setting[0])
                        continue
                    }

                    parse_command_keybind(command, setting[:], p.line)
                case .widget:
                    command, ok := reflect.enum_from_name(Editor_Command, setting[0])

                    if !ok {
                        log.errorf(UNKNOWN_COMMAND, p.line, setting[0])
                        continue
                    }

                    parse_command_keybind(command, setting[:], p.line)
                }

            case .interface:
                if p.subsection == .unspecified {
                    log.errorf(MISSING_SUBHEADING, p.line)
                    return false
                }

                if len(setting) != 2 {
                    log.errorf(INCORRECT_FORMAT, p.line, "setting value", line)
                    continue
                }

                switch p.subsection {
                case .unspecified, .global, .editor, .widget:
                    log.errorf(INVALID_SUBHEADING, p.line)
                    return false
                case .ui:
                    // TODO: Handle UI parsing
                case .colorscheme:
                    v, ok := reflect.enum_from_name(Face, setting[0])

                    if !ok {
                        log.errorf(UNKNOWN_FACE, p.line, setting[0])
                        continue
                    }

                    colorscheme[v] = hex_to_color(setting[1])
                }
            }
        }
    }

    return
}

parse_command_keybind :: proc(cmd: Command_Group, setting: []string, line: int) {
    for i in 1..<len(setting) {
        k := setting[i]

        if !strings.starts_with(k, "<") || !strings.ends_with(k, ">") {
            log.errorf(INCORRECT_FORMAT, line, "<keybinding>", k)
            return
        }

        bind := k[1:len(k) - 1]

        switch t in cmd {
        case Global_Command:
            keymaps.global[strings.clone(bind)] = t
            bragi.settings.keybindings_table[strings.clone(bind)] = Command(t)
        case Editor_Command:
            keymaps.editor[strings.clone(bind)] = t
            bragi.settings.keybindings_table[strings.clone(bind)] = Command(t)
        case Widget_Command:
            keymaps.widget[strings.clone(bind)] = t
            bragi.settings.keybindings_table[strings.clone(bind)] = Command(t)
        }
    }
}
