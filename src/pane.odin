package main

import "core:log"
import "core:strings"
import "core:time"

CURSOR_BLINK_MAX_COUNT :: 6
CURSOR_BLINK_TIMEOUT   :: 500 * time.Millisecond
CURSOR_RESET_TIMEOUT   :: 50  * time.Millisecond

Pane_Mode :: enum u8 {
    Line_Wrappings,
}

Pane_Flag :: enum u8 {
    Need_Full_Redraw,
}

Pane :: struct {
    cursor_showing:     bool,
    cursor_blink_count: int,
    cursor_blink_timer: time.Tick,
    last_keystroke:     time.Tick,

    buffer:             ^Buffer,
    contents:           strings.Builder,

    modes:              bit_set[Pane_Mode; u8],
    flags:              bit_set[Pane_Flag; u8],

    // rendering stuff
    rect:               Rect,
    texture:            ^Texture,
    size_of_gutter:     i32,
    y_offset:           i32,
    visible_rows:       i32,
    x_offset:           i32,
    visible_columns:    i32,
}

pane_create :: proc(buffer: ^Buffer = nil, allocator := context.allocator) -> ^Pane {
    log.debug("creating new pane")
    result := new(Pane)

    result.cursor_showing = true
    result.cursor_blink_count = 0
    result.cursor_blink_timer = time.tick_now()

    if buffer == nil {
        result.buffer = buffer_create("", allocator)
    } else {
        result.buffer = buffer
    }

    append(&open_panes, result)
    update_all_pane_textures()
    return result
}

pane_destroy :: proc(p: ^Pane) {
    p.buffer = nil
    strings.builder_destroy(&p.contents)
    free(p)
}

update_and_draw_panes :: proc() {
    should_cursor_blink :: proc(p: ^Pane) -> bool {
        return p.cursor_blink_count < CURSOR_BLINK_MAX_COUNT &&
            time.tick_diff(p.cursor_blink_timer, time.tick_now()) > CURSOR_BLINK_TIMEOUT
    }

    for pane in open_panes {
        // is_focused := pane == active_pane

        assert(pane.buffer != nil)
        assert(pane.texture != nil)

        if buffer_update(pane.buffer, &pane.contents) {
            pane.flags += {.Need_Full_Redraw}
        }

        if time.tick_diff(pane.last_keystroke, time.tick_now()) < CURSOR_RESET_TIMEOUT {
            pane.cursor_showing = true
            pane.cursor_blink_count = 0
            pane.cursor_blink_timer = time.tick_now()
            pane.flags += {.Need_Full_Redraw}
        }

        if should_cursor_blink(pane) {
            pane.cursor_showing = !pane.cursor_showing
            pane.cursor_blink_count += 1
            pane.cursor_blink_timer = time.tick_now()

            if pane.cursor_blink_count >= CURSOR_BLINK_MAX_COUNT {
                pane.cursor_showing = true
            }

            pane.flags += {.Need_Full_Redraw}
        }

        if .Need_Full_Redraw not_in pane.flags {
            draw_texture(pane.texture, nil, &pane.rect)
            continue
        }

        set_target(pane.texture)
        prepare_for_drawing()

        font := fonts_map[.Editor]
        sx, sy: f32

        for r in strings.to_string(pane.contents) {
            if r == '\n' {
                sy += f32(get_line_height(font))
                sx = 0
                continue
            }

            glyph := find_or_create_glyph(font, r)

            src := Rect{f32(glyph.x), f32(glyph.y), f32(glyph.w), f32(glyph.h)}
            dest := Rect{sx, sy, src.w, src.h}
            set_foreground(font.texture, 255, 255, 255)
            draw_texture(font.texture, &src, &dest)
            sx += f32(glyph.xadvance)
        }

        set_target()

        pane.flags -= {.Need_Full_Redraw}
    }
}

update_all_pane_textures :: #force_inline proc() {
    // NOTE(nawe) should be safe to clean up textures here since we're probably recreating them due to the change in size
    default_font := fonts_map[.Editor]

    pane_width := f32(window_width / i32(len(open_panes)))
    pane_height := f32(window_height)

    for &pane, index in open_panes {
        texture_destroy(pane.texture)

        pane.rect = { pane_width * f32(index), 0, pane_width, pane_height }
        pane.texture = texture_create(.TARGET, i32(pane_width), i32(pane_height))
        pane.visible_columns = (i32(pane.rect.w) - pane.size_of_gutter) / default_font.xadvance - 1
        pane.visible_rows = i32(pane.rect.h) / get_line_height(default_font)

        if .Line_Wrappings in pane.modes {
            recalculate_line_wrappings(pane)
        }
    }
}

recalculate_line_wrappings :: proc(pane: ^Pane) {
    unimplemented()
}
