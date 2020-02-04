class Vls.GirDocumentation {
    private Vala.CodeContext context;

    /**
     * Create a new holder for GIR docs by adding all GIRs found in
     * `/usr/share/gir-1.0` and `/usr/local/share/gir-1.0`
     */
    public GirDocumentation (Gee.Collection<Vala.SourceFile> packages) {
        context = new Vala.CodeContext ();
        context.profile = Vala.Profile.GOBJECT;
        context.add_define ("GOBJECT");
        context.gir_directories = { "/usr/share", "/usr/local/share" };

        // add packages
        var added = new Gee.HashSet<string> ();
        context.add_external_package ("GObject-2.0");
        added.add ("GObject-2.0");
        context.add_external_package ("GLib-2.0");
        added.add ("GLib-2.0");
        foreach (string gir_directory in context.gir_directories) {
            File dir = File.new_for_path (@"$gir_directory/gir-1.0");
            try {
                var enumerator = dir.enumerate_children (
                    "standard::*",
                    FileQueryInfoFlags.NONE);
                FileInfo? file_info;
                while ((file_info = enumerator.next_file ()) != null) {
                    if ((file_info.get_file_type () != FileType.REGULAR &&
                        file_info.get_file_type () != FileType.SYMBOLIC_LINK) ||
                        file_info.get_is_backup () || file_info.get_is_hidden () ||
                        !file_info.get_name ().has_suffix (".gir"))
                        continue;
                    string gir_pkg = Path.get_basename (file_info.get_name ());
                    gir_pkg = gir_pkg.substring (0, gir_pkg.length - ".gir".length);
                    Vala.SourceFile? vapi_pkg_match = packages.first_match (
                        pkg => pkg.gir_version != null && @"$(pkg.gir_namespace)-$(pkg.gir_version)" == gir_pkg);
                    if (!added.contains (gir_pkg) && vapi_pkg_match != null) {
                        debug (@"adding GIR `$gir_pkg' for package `$(vapi_pkg_match.package_name)'");
                        context.add_external_package (gir_pkg);
                        added.add (gir_pkg);
                    }
                }
            } catch (Error e) {
                debug (@"could not enumerate dir `$(dir.get_path ())': $(e.message)");
            }
        }

        string missed = "";
        packages.filter (pkg => !added.any_match (pkg_name => pkg.gir_version != null && pkg_name == @"$(pkg.gir_namespace)-$(pkg.gir_version)"))
            .foreach (vapi_pkg => {
                if (missed.length > 0)
                    missed += ", ";
                missed += vapi_pkg.package_name;
                return true;
            });
        debug (@"did not add GIRs for these packages: $missed");

        // add some types manually
        Vala.SourceFile? sr_file = null;
        foreach (var source_file in context.get_source_files ()) {
            if (source_file.filename.has_suffix ("GLib-2.0.gir"))
                sr_file = source_file;
        }
        var sr_begin = Vala.SourceLocation (null, 1, 1);
        var sr_end = sr_begin;

        // ... add bool
        var bool_struct = new Vala.Struct ("bool", new Vala.SourceReference (sr_file, sr_begin, sr_end));
        bool_struct.add_method (new Vala.Method ("to_string", new Vala.UnresolvedType.from_symbol (new Vala.UnresolvedSymbol (null, "string"))));
        context.root.add_struct (bool_struct);

        // ... add GLib namespace
        context.root.add_namespace (new Vala.Namespace ("GLib", new Vala.SourceReference (sr_file, sr_begin, sr_end)));

        // compile once
        Vala.CodeContext.push (context);
        var parser = new Vala.Parser ();
        parser.parse (context);
        var gir_parser = new Vala.GirParser ();
        gir_parser.parse (context);
        context.check ();
        Vala.CodeContext.pop ();
    }

    /**
     * Decide how to render a comment.
     */
    public static string? render_comment (Vala.Comment comment) {
        return comment.content; // TODO: render
    }

    /**
     * Find the symbol from this 
     */
    public Vala.Symbol? find_gir_symbol (Vala.Symbol sym) {
        var symbols = new Queue<Vala.Symbol> ();
        Vala.Symbol? gir_sym = null;

        for (Vala.Symbol? current_sym = sym;
             current_sym != null && current_sym != context.root && current_sym.to_string () != "(root namespace)";
             current_sym = current_sym.parent_symbol) {
            symbols.push_head (current_sym);
        }

        gir_sym = context.root.scope.lookup (symbols.pop_head ().name);
        while (!symbols.is_empty () && gir_sym != null)
            gir_sym = gir_sym.scope.get_symbol_table ()[symbols.pop_head ().name];

        if (!symbols.is_empty ())
            return null;

        return gir_sym;
    }
}
