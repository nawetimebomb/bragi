package main

import "core:fmt"
import "core:log"
import "core:reflect"
import "core:strconv"
import "core:strings"

import "core:os"

DEFAULT_COLORSCHEME :: #load("../res/colorschemes/default.bragi")

Color :: distinct [3]u8

Face :: enum {
    background,
    foreground,
    builtin,
    comment,
    constant,
    default,
    function_name,
    keyword,
    match_delimiter,
    match_highlight,
    region,
    string,
    variable_name,
}

Colorscheme :: struct {
    name: string,
    colors: map[Face]Color,
}

// TODO: This might just be temporary, but I'm looking for ideas on how to register
// these from files instead.
reload_theme :: proc() {
    data, ok := os.read_entire_file_from_filename("../res/colorschemes/default.bragi")
    register_colorscheme(data)
    delete(data)
}

register_colorscheme :: proc(data: []u8) {
    str := string(data)
    cs := &bragi.settings.cs

    for line in strings.split_lines_iterator(&str) {
        s := strings.split(line, ":", context.temp_allocator)
        key := strings.trim_space(s[0])
        value := strings.trim_space(s[1])

        if key == "name" {
            cs.name = value
        } else {
            if key, ok := reflect.enum_from_name(Face, key); ok {
                cs.colors[key] = hex_to_color(value)
            }
        }
    }
}

hex_to_color :: proc(hex_str: string) -> Color {
    rgb: Color
    value, ok := strconv.parse_int(hex_str, 16)

    if !ok {
        log.errorf("Cannot parse color {0}", hex_str)
        return rgb
    }

    rgb.r = u8((value >> 16) & 0xFF)
    rgb.g = u8((value >> 8) & 0xFF)
    rgb.b = u8(value & 0xFF)

    return rgb
}
