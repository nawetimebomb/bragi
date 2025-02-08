package tokenizer

import "core:slice"

tokenize_odin :: proc(s: ^string) -> []Token_Kind {
    tokenizer_init(s)

    COMMON_DELIMITERS        :: "().,:;[]{} \n\t"
    MULTI_LINE_COMMENT_END   :: "*/"
    MULTI_LINE_COMMENT_START :: "/*"
    SINGLE_LINE_COMMENT      :: "//"

    BUILTINS := [?]string{
        "len", "cap", "size_of", "align_of", "offset_of", "offset_of_selector",
        "offset_of_member", "offset_of_by_string", "type_of", "type_info_of",
        "typeid_of", "swizzle", "complex", "quaternion", "real", "imag",
        "jmag", "kmag", "conj", "expand_values", "min", "max", "abs",
        "clamp", "soa_zip", "soa_unzip", "raw_data", "container_of",
        "init_global_temporary_allocator", "copy_slice", "copy_from_string",
        "unordered_remove", "ordered_remove", "remove_range", "pop",
        "pop_safe", "pop_front", "pop_front_safe", "delete_string",
        "delete_cstring", "delete_dynamic_array", "delete_slice",
        "delete_map", "new", "new_clone", "make_slice", "make_dynamic_array",
        "make_dynamic_array_len", "make_dynamic_array_len_cap", "make_map",
        "make_map_cap", "make_multi_pointer", "clear_map", "reserve_map",
        "shrink_map", "delete_key", "append_elem", "non_zero_append_elem",
        "append_elems", "non_zero_append_elems", "append_elem_string",
        "non_zero_append_elem_string", "append_string", "append_nothing",
        "inject_at_elem", "inject_at_elems", "inject_at_elem_string",
        "assign_at_elem", "assign_at_elems", "assign_at_elem_string",
        "clear_dynamic_array", "reserve_dynamic_array", "non_zero_reserve_dynamic_array",
        "resize_dynamic_array", "non_zero_resize_dynamic_array", "map_insert",
        "map_upsert", "map_entry", "card", "assert", "ensure", "panic",
        "unimplemented", "assert_contextless", "ensure_contextless",
        "raw_soa_footer_slice", "raw_soa_footer_dynamic_array",
        "make_soa_aligned", "make_soa_slice", "make_soa_dynamic_array",
        "make_soa_dynamic_array_len", "make_soa_dynamic_array_len_cap",
        "panic_contextless", "unimplemented_contextless", "resize_soa",
        "non_zero_resize_soa", "reserve_soa", "non_zero_reserve_soa",
        "append_soa_elem", "non_zero_append_soa_elem", "append_soa_elems",
        "non_zero_append_soa_elems", "unordered_remove_soa", "ordered_remove_soa",
    }
    CONSTANTS := [?]string{ "false", "nil", "true", "---" }
    KEYWORDS := [?]string{
        "asm", "auto_cast", "bit_set", "break", "case", "cast",
        "context", "continue", "defer", "delete", "distinct", "do", "dynamic",
        "else", "enum", "fallthrough", "for", "foreign", "if",
        "import", "in", "map", "not_in", "or_else", "or_return",
        "package", "proc", "return", "struct", "switch", "transmute",
        "typeid", "union", "using", "when", "where", "#load",
    }
    TYPES := [?]string{
        "bool", "b8", "b16", "b32", "b64",
        "int", "i8", "i16", "i32", "i64", "i128",
        "uint", "u8", "u16", "u32", "u64", "u128", "uintptr",
        "i16le", "i32le", "i64le", "i128le", "u16le", "u32le", "u64le", "u128le",
        "i16be", "i32be", "i64be", "i128be", "u16be", "u32be", "u64be", "u128be",
        "f16", "f32", "f64", "f16le", "f32le", "f64le", "f16be", "f32be", "f64be",
        "complex32", "complex64", "complex128",
        "quaternion64", "quaternion128", "quaternion256",
        "rune", "string", "cstring", "rawptr", "typeid", "any",
    }
    STRING_DELIMITERS := [?]byte{ '\'', '"', '`' }

    for !tokenizer_complete() {
        skip_all_whitespaces()

        switch {
        case is_char_in(STRING_DELIMITERS[:]):
            start := T.offset
            scan_through_until_after_char(get_char())
            end := T.offset
            save_tokens(.string, start, end)
        case is_number():
            start := T.offset
            scan_through_until_proc_false(is_number)
            end := T.offset
            save_tokens(.constant, start, end)
        case :
            start := T.offset
            length := scan_through_until_delimiter(COMMON_DELIMITERS)
            end := T.offset
            word := S[start:end]

            switch {
            case word == SINGLE_LINE_COMMENT:
                scan_through_until_end_of_line()
                end = T.offset
                save_tokens(.comment, start, end)
            case word == MULTI_LINE_COMMENT_START:
                scan_through_until_word(MULTI_LINE_COMMENT_END)
                end = T.offset
                save_tokens(.comment, start, end)
            case slice.contains(BUILTINS[:], word):
                save_tokens(.builtin, start, end)
            case slice.contains(CONSTANTS[:], word):
                save_tokens(.constant, start, end)
            case slice.contains(KEYWORDS[:], word):
                save_tokens(.keyword, start, end)
            case slice.contains(TYPES[:], word):
                save_tokens(.type, start, end)
            }
        }
    }

    return tokenizer_finish()
}
