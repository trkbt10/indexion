///|
fn temp_config_dir(prefix : String) -> String {
  prefix
}

///|
fn remove_file_if_exists(path : String) -> Unit {
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
fn remove_dir_if_exists(path : String) -> Unit {
  if @fs.path_exists(path) {
    @fs.remove_dir(path) catch {
      _ => ()
    }
  }
}

///|
test "config: parse_reconcile_toml_config supports nested sections" {
  let input =
    #|[reconcile]
    #|doc_scope = "tree-docs"
    #|doc_paths = ["docs/**/*.md", "spec/**/*.toml"]
    #|review_results_path = ".indexion/reconcile/reviews.json"
    #|threshold_seconds = 120
    #|
    #|[reconcile.mapping]
    #|allow_file_fallback = false
    #|
    #|[reconcile.output]
    #|default_format = "md"
    #|
    #|[reconcile.time]
    #|git_preferred = true
    #|mtime_fallback = false
    #|
    #|[reconcile.logical_review]
    #|mode = "off"
  let config = parse_reconcile_toml_config(input)
  assert_eq(config.doc_scope, Some("tree-docs"))
  assert_true(config.doc_paths is Some(_))
  assert_eq(config.doc_paths.unwrap()[0], "docs/**/*.md")
  assert_eq(
    config.review_results_path,
    Some(".indexion/reconcile/reviews.json"),
  )
  assert_eq(config.threshold_seconds, Some(120))
  assert_eq(config.allow_file_fallback, Some(false))
  assert_eq(config.format, Some("md"))
  assert_eq(config.mtime_fallback, Some(false))
  assert_eq(config.logical_review_mode, Some("off"))
}

///|
test "config: reconcile doc scope helpers normalize presets" {
  assert_eq(normalize_reconcile_doc_scope("package-docs"), "package-docs")
  assert_eq(normalize_reconcile_doc_scope("tree-docs"), "tree-docs")
  assert_eq(normalize_reconcile_doc_scope("tree_docs"), "custom")
  assert_eq(reconcile_doc_scope_paths("package-docs"), [
    "README.md", "docs/**/*.md",
  ])
  assert_eq(reconcile_doc_scope_specs("tree-docs"), ["markdown"])
}

///|
test "config: resolve_reconcile_document_scope materializes shared path scope" {
  let selection = resolve_reconcile_document_scope("package-docs")
  assert_eq(selection.scope_name, "package-docs")
  assert_eq(selection.doc_paths, ["README.md", "docs/**/*.md"])
  assert_eq(selection.doc_specs, ["markdown"])
  let subject = @scope.PathSubject::new("README.md", additional_paths=[
    "/tmp/project/README.md",
  ])
  assert_true(selection.path_scope.matches(subject))
}

///|
test "config: load_reconcile_file_config loads target-local indexion config" {
  let dir = temp_config_dir(".indexion/src-config-load-")
  remove_dir_if_exists(dir)
  ensure_dir_recursive(dir)
  let config_path = join_path(dir, ".indexion.toml")
  remove_file_if_exists(config_path)
  let config_content =
    #|[reconcile]
    #|index_dir = ".cache/reconcile"
    #|review_results_path = ".indexion/reconcile/reviews.json"
  @fs.write_string_to_file(config_path, config_content) catch {
    _ => ()
  }
  let discovered = find_indexion_config_path(dir)
  let file_config = load_reconcile_file_config(discovered)
  assert_eq(discovered, config_path)
  assert_eq(file_config.index_dir, Some(".cache/reconcile"))
  assert_eq(
    resolve_config_path_value(dir, discovered, file_config.index_dir.unwrap()),
    join_path(dir, ".cache/reconcile"),
  )
  remove_file_if_exists(config_path)
  remove_dir_if_exists(dir)
}

///|
test "config: path helpers normalize and derive file parts" {
  assert_eq(normalize_path("foo//bar/../baz"), "foo/baz")
  assert_eq(basename("docs/api/readme.md"), "readme.md")
  assert_eq(extension("docs/api/readme.md"), ".md")
  assert_eq(relative_to("docs", "docs/api/readme.md"), "api/readme.md")
}

///|
test "config: find_nearest_marker_dir resolves nearest project marker" {
  let dir = temp_config_dir(".indexion/src-config-package-dir-")
  let package_dir = join_path(dir, "cmd/indexion/plan/reconcile")
  ensure_dir_recursive(package_dir)
  let manifest = join_path(package_dir, "package.json")
  let source = join_path(package_dir, "cli.mbt")
  @fs.write_string_to_file(manifest, "") catch {
    _ => ()
  }
  @fs.write_string_to_file(source, "fn main() -> Unit { ignore(()) }") catch {
    _ => ()
  }
  assert_eq(
    find_nearest_marker_dir(dir, source, ["package.json"]),
    Some(package_dir),
  )
  remove_file_if_exists(source)
  remove_file_if_exists(manifest)
  remove_dir_if_exists(package_dir)
  remove_dir_if_exists(join_path(dir, "cmd/indexion/plan"))
  remove_dir_if_exists(join_path(dir, "cmd/indexion"))
  remove_dir_if_exists(join_path(dir, "cmd"))
  remove_dir_if_exists(dir)
}

///|
test "config: find_nearest_marker_dir supports wildcard markers" {
  let dir = temp_config_dir(".indexion/src-config-wildcard-dir-")
  let project_dir = join_path(dir, "apps/server")
  ensure_dir_recursive(project_dir)
  let marker = join_path(project_dir, "server.csproj")
  let source = join_path(project_dir, "Program.cs")
  @fs.write_string_to_file(marker, "") catch {
    _ => ()
  }
  @fs.write_string_to_file(source, "class Program {}") catch {
    _ => ()
  }
  assert_eq(
    find_nearest_marker_dir(dir, source, ["*.csproj"]),
    Some(project_dir),
  )
  remove_file_if_exists(source)
  remove_file_if_exists(marker)
  remove_dir_if_exists(project_dir)
  remove_dir_if_exists(join_path(dir, "apps"))
  remove_dir_if_exists(dir)
}
