/* formatter.vala
 *
 * Copyright 2022 JCWasmx86 <JCWasmx86@t-online.de>
 *
 * This file is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 *
 * This file is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

using Gee;
using Lsp;

errordomain FormattingError {
    FORMAT,
    READ
}

namespace Vls.Formatter {
    TextEdit format (FormattingOptions options,
                     CodeStyleAnalyzer? analyzed_style,
                     Vala.SourceFile source, Range? range = null,
                     Cancellable? cancellable = null) throws FormattingError, Error {
        // SEARCH_PATH_FROM_ENVP does not seem to be available even in quite fast distros like Fedora 35,
        // so we have to use a SubprocessLauncher and call set_environ()
        var launcher = new SubprocessLauncher (SubprocessFlags.STDERR_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDIN_PIPE);
        launcher.set_environ (Environ.get ());
        Subprocess subprocess = launcher.spawnv (get_uncrustify_args (source, options, analyzed_style, cancellable));
        string stdin_buf;
        if (range == null) {
            stdin_buf = source.content;
        } else {
            var from = (long)Util.get_string_pos (source.content, range.start.line, range.start.character);
            var to = (long)Util.get_string_pos (source.content, range.end.line, range.end.character);
            stdin_buf = source.content[from:to];
        }
        string? stdout_buf = null, stderr_buf = null;
        subprocess.communicate_utf8 (stdin_buf, cancellable, out stdout_buf, out stderr_buf);
        if (!subprocess.get_successful ()) {
            if (stderr_buf != null && stderr_buf.strip ().length > 0) {
                throw new FormattingError.FORMAT ("%s", stderr_buf);
            } else {
                throw new FormattingError.READ ("uncrustify failed with error code %d", subprocess.get_exit_status ());
            }
        }
        Range edit_range;
        if (range != null) {
            edit_range = range;
        } else {
            int last_nl_pos;
            uint nl_count = Util.count_chars_in_string (stdin_buf, '\n', out last_nl_pos);
            edit_range = new Range () {
                start = new Position () {
                    line = 0,
                    character = 0
                },
                end = new Position () {
                    line = nl_count + 1,
                    // handle trailing newline
                    character = last_nl_pos == stdin_buf.length - 1 ? 1 : 0
                }
            };
        }
        return new TextEdit (edit_range, stdout_buf);
    }

    string[] get_uncrustify_args (Vala.SourceFile source, FormattingOptions options, CodeStyleAnalyzer? analyzed_style, Cancellable? cancellable = null) {
        // Check if the project has a local uncrustify config file and use that instead
        var cwd = File.new_for_path (Environment.get_current_dir ());
        string[] config_paths = { ".uncrustify.cfg", "uncrustify.cfg" };
        foreach (string filename in config_paths) {
            var child = cwd.get_child (filename);
            if (child.query_exists (cancellable)) {
                return { "uncrustify", "-c", child.get_path (), "--assume", source.filename, "-q" };
            }
        }

        // No config file found... Use defaults
        var conf = new HashMap<string, string> ();
        // https://github.com/uncrustify/uncrustify/blob/master/documentation/htdocs/default.cfg
        conf["indent_with_tabs"] = "%d".printf (options.insertSpaces ? 0 : 1);
        conf["nl_end_of_file"] = options.insertFinalNewline ? "force" : "remove";
        conf["nl_end_of_file_min"] = "%d".printf (options.trimFinalNewlines ? 1 : 0);
        conf["output_tab_size"] = "%u".printf (options.tabSize);
        conf["indent_columns"] = "4";
        conf["indent_align_string"] = "true";
        conf["indent_xml_string"] = "4";
        conf["indent_namespace"] = "true";
        conf["indent_class"] = "true";
        conf["indent_var_def_cont"] = "true";
        conf["indent_func_def_param"] = "true";
        conf["indent_func_proto_param"] = "true";
        conf["indent_func_class_param"] = "true";
        conf["indent_func_ctor_var_param"] = "true";
        conf["indent_template_param"] = "true";
        conf["indent_member"] = "1";
        conf["indent_paren_close"] = "2";
        conf["indent_align_assign"] = "false";
        conf["indent_oc_block_msg_xcode_style"] = "true";
        conf["indent_oc_block_msg_from_keyword"] = "true";
        conf["indent_oc_block_msg_from_colon"] = "true";
        conf["indent_oc_block_msg_from_caret"] = "true";
        conf["indent_oc_block_msg_from_brace"] = "true";
        conf["newlines"] = "auto";
        conf["sp_arith"] = "force";
        conf["sp_assign"] = "force";
        conf["sp_assign_default"] = "force";
        conf["sp_before_assign"] = "force";
        conf["sp_after_assign"] = "force";
        conf["sp_enum_assign"] = "force";
        conf["sp_enum_after_assign"] = "force";
        conf["sp_bool"] = "force";
        conf["sp_compare"] = "force";
        conf["sp_inside_paren"] = "remove";
        conf["sp_paren_paren"] = "remove";
        conf["sp_cparen_oparen"] = "force";
        conf["sp_paren_brace"] = "force";
        conf["sp_before_ptr_star"] = "remove";
        conf["sp_before_unnamed_ptr_star"] = "remove";
        conf["sp_between_ptr_star"] = "force";
        conf["sp_after_ptr_star"] = "force";
        conf["sp_after_ptr_star_func"] = "force";
        conf["sp_ptr_star_paren"] = "force";
        conf["sp_before_ptr_star_func"] = "force";
        conf["sp_before_byref"] = "force";
        conf["sp_after_byref_func"] = "remove";
        conf["sp_before_byref_func"] = "force";
        conf["sp_before_angle"] = "remove";
        conf["sp_inside_angle"] = "remove";
        conf["sp_after_angle"] = "remove";
        conf["sp_angle_paren"] = "force";
        conf["sp_angle_word"] = "force";
        conf["sp_before_sparen"] = "force";
        conf["sp_inside_sparen"] = "remove";
        conf["sp_after_sparen"] = "remove";
        conf["sp_sparen_brace"] = "force";
        conf["sp_special_semi"] = "remove";
        conf["sp_before_semi_for"] = "remove";
        conf["sp_before_semi_for_empty"] = "force";
        conf["sp_after_semi_for_empty"] = "force";
        conf["sp_before_square"] = "remove";
        conf["sp_before_squares"] = "remove";
        conf["sp_inside_square"] = "remove";
        conf["sp_after_comma"] = "force";
        conf["sp_before_ellipsis"] = "remove";
        conf["sp_after_class_colon"] = "force";
        conf["sp_before_class_colon"] = "force";
        conf["sp_after_constr_colon"] = "ignore";
        conf["sp_before_constr_colon"] = "ignore";
        conf["sp_after_operator"] = "force";
        conf["sp_after_cast"] = "force";
        conf["sp_inside_paren_cast"] = "remove";
        conf["sp_sizeof_paren"] = "force";
        conf["sp_inside_braces_enum"] = "force";
        conf["sp_inside_braces_struct"] = "force";
        conf["sp_inside_braces"] = "force";
        conf["sp_inside_braces_empty"] = "remove";
        conf["sp_type_func"] = "remove";
        conf["sp_inside_fparens"] = "remove";
        conf["sp_inside_fparen"] = "remove";
        conf["sp_inside_tparen"] = "remove";
        conf["sp_after_tparen_close"] = "remove";
        conf["sp_square_fparen"] = "force";
        conf["sp_fparen_brace"] = "force";
        if (analyzed_style != null && analyzed_style.average_spacing_before_parens > 0) {
            conf["sp_func_proto_paren"] = "force";
            conf["sp_func_def_paren"] = "force";
            conf["sp_func_class_paren"] = "force";
            conf["sp_func_call_paren"] = "force";
        } else {
            conf["sp_func_proto_paren"] = "remove";
            conf["sp_func_def_paren"] = "remove";
            conf["sp_func_class_paren"] = "remove";
            conf["sp_func_call_paren"] = "remove";
        }
        conf["sp_func_call_paren_empty"] = "ignore";
        // It is really "set func_call_user _"
        // conf["set func_call_user"] = "C_ NC_ N_ Q_ _";
        conf["sp_return_paren"] = "force";
        conf["sp_attribute_paren"] = "force";
        conf["sp_defined_paren"] = "force";
        conf["sp_throw_paren"] = "force";
        conf["sp_after_throw"] = "force";
        conf["sp_catch_paren"] = "force";
        conf["sp_else_brace"] = "force";
        conf["sp_brace_else"] = "force";
        conf["sp_brace_typedef"] = "force";
        conf["sp_catch_brace"] = "force";
        conf["sp_brace_catch"] = "force";
        conf["sp_finally_brace"] = "force";
        conf["sp_brace_finally"] = "force";
        conf["sp_try_brace"] = "force";
        conf["sp_getset_brace"] = "force";
        conf["sp_word_brace_ns"] = "force";
        conf["sp_before_dc"] = "remove";
        conf["sp_after_dc"] = "remove";
        conf["sp_cond_colon"] = "force";
        conf["sp_cond_colon_before"] = "force";
        conf["sp_cond_question"] = "force";
        conf["sp_cond_question_after"] = "force";
        conf["sp_cond_ternary_short"] = "force";
        conf["sp_case_label"] = "force";
        conf["sp_cmt_cpp_start"] = "force";
        conf["sp_endif_cmt"] = "remove";
        conf["sp_after_new"] = "force";
        conf["sp_before_tr_cmt"] = "force";
        conf["align_keep_extra_space"] = "true";
        conf["nl_assign_leave_one_liners"] = "true";
        conf["nl_class_leave_one_liners"] = "true";
        conf["nl_enum_brace"] = "remove";
        conf["nl_struct_brace"] = "remove";
        conf["nl_union_brace"] = "remove";
        conf["nl_if_brace"] = "remove";
        conf["nl_brace_else"] = "remove";
        conf["nl_elseif_brace"] = "remove";
        conf["nl_else_brace"] = "remove";
        conf["nl_else_if"] = "remove";
        conf["nl_brace_finally"] = "remove";
        conf["nl_finally_brace"] = "remove";
        conf["nl_try_brace"] = "remove";
        conf["nl_getset_brace"] = "remove";
        conf["nl_for_brace"] = "remove";
        conf["nl_catch_brace"] = "remove";
        conf["nl_brace_catch"] = "remove";
        conf["nl_brace_square"] = "remove";
        conf["nl_brace_fparen"] = "remove";
        conf["nl_while_brace"] = "remove";
        conf["nl_using_brace"] = "remove";
        conf["nl_do_brace"] = "remove";
        conf["nl_brace_while"] = "remove";
        conf["nl_switch_brace"] = "remove";
        conf["nl_before_throw"] = "remove";
        conf["nl_namespace_brace"] = "remove";
        conf["nl_class_brace"] = "remove";
        conf["nl_class_init_args"] = "remove";
        conf["nl_class_init_args"] = "remove";
        conf["nl_func_type_name"] = "remove";
        conf["nl_func_type_name_class"] = "remove";
        conf["nl_func_proto_type_name"] = "remove";
        conf["nl_func_paren"] = "remove";
        conf["nl_func_def_paren"] = "remove";
        conf["nl_func_decl_start"] = "remove";
        conf["nl_func_def_start"] = "remove";
        conf["nl_func_decl_end"] = "remove";
        conf["nl_func_def_end"] = "remove";
        conf["nl_func_decl_empty"] = "remove";
        conf["nl_func_def_empty"] = "remove";
        conf["nl_fdef_brace"] = "remove";
        conf["nl_return_expr"] = "remove";
        conf["nl_after_func_proto_group"] = "2";
        conf["nl_after_func_body"] = "2";
        conf["nl_after_func_body_class"] = "2";
        conf["eat_blanks_before_close_brace"] = "true";
        conf["pp_indent_count"] = "0";
        string[] args = { "uncrustify", "-c", "-", "--assume", source.filename, "-q" };
        foreach (var entry in conf.entries) {
            args += "--set";
            args += @"$(entry.key)=$(entry.value)";
        }
        return args;
    }
}
