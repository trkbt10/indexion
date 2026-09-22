///|
/// Tests for layered spec loading: `load_from_dirs` composes several spec
/// directories so a project can replace a single installed spec without
/// copying the rest of the set.

///|
fn overlay_temp_root(prefix : String) -> String {
  "/tmp/indexion-registry-test/" + prefix
}

///|
/// Minimal but complete spec text so `parse_kgf` accepts it. `marker` is a
/// token name unique to each layer, which is how a test tells which file won.
fn overlay_spec_text(
  language : String,
  source_ext : String,
  marker : String,
) -> String {
  "kgf 0.6\n" +
  "language: " +
  language +
  "\n" +
  "sources: " +
  source_ext +
  "\n" +
  "\n=== lex\n" +
  "SKIP /[ \\t]+/\n" +
  "TOKEN NL /\\r?\\n/\n" +
  "TOKEN " +
  marker +
  " /" +
  marker +
  "/\n" +
  "TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/\n" +
  "\n=== grammar\n" +
  "Module -> Ident*\n" +
  "\n=== attrs\n" +
  "Ident: identifier\n" +
  "\n=== resolver\n" +
  "sources: " +
  source_ext +
  "\n"
}

///|
fn write_overlay_spec(
  dir : String,
  file_name : String,
  language : String,
  source_ext : String,
  marker : String,
) -> Unit {
  @config.ensure_dir_recursive(dir)
  @fs.write_string_to_file(
    dir + "/" + file_name,
    overlay_spec_text(language, source_ext, marker),
  ) catch {
    _ => ()
  }
}

///|
fn remove_overlay_tree(paths : Array[String]) -> Unit {
  for path in paths {
    if @fs.path_exists(path) {
      let removed = @fs.remove_file(path) catch { _ => () }
      ignore(removed)
      @fs.remove_dir(path) catch {
        _ => ()
      }
    }
  }
}

///|
/// True when the registry's spec for `language` declares a token named `kind`.
fn spec_has_token(
  registry : KGFRegistry,
  language : String,
  kind : String,
) -> Bool {
  match registry.get_spec(language) {
    Some(spec) => {
      for token in spec.get_tokens() {
        if token.name == kind {
          return true
        }
      }
      false
    }
    None => false
  }
}

///|
test "registry: a later directory replaces a spec by language name" {
  let root = overlay_temp_root("registry-overlay-by-name-")
  let base = root + "/base"
  let overlay = root + "/overlay"
  // The overlay uses a different file name and a different category-style
  // subdirectory, so only the `language:` header can match them up.
  write_overlay_spec(
    base + "/programming",
    "demo.kgf",
    "overlay-demo",
    ".odemo",
    "BASEMARK",
  )
  write_overlay_spec(
    overlay, "patched-demo.kgf", "overlay-demo", ".odemo", "OVERLAYMARK",
  )
  let registry = KGFRegistry::load_from_dirs([base, overlay])
  assert_eq(registry.spec_count(), 1)
  assert_true(spec_has_token(registry, "overlay-demo", "OVERLAYMARK"))
  assert_false(spec_has_token(registry, "overlay-demo", "BASEMARK"))
  // The overlay must also reclaim the extension, or the replacement would be
  // unreachable through file detection.
  assert_eq(registry.detect_from_path("a/b.odemo"), Some("overlay-demo"))
  remove_overlay_tree([
    base + "/programming/demo.kgf",
    base + "/programming",
    base,
    overlay + "/patched-demo.kgf",
    overlay,
    root,
  ])
}

///|
test "registry: layering keeps specs the overlay does not redefine" {
  let root = overlay_temp_root("registry-overlay-keeps-")
  let base = root + "/base"
  let overlay = root + "/overlay"
  write_overlay_spec(base, "kept.kgf", "overlay-kept", ".okept", "KEPTMARK")
  write_overlay_spec(base, "demo.kgf", "overlay-demo", ".odemo", "BASEMARK")
  write_overlay_spec(
    overlay, "demo.kgf", "overlay-demo", ".odemo", "OVERLAYMARK",
  )
  let registry = KGFRegistry::load_from_dirs([base, overlay])
  assert_eq(registry.spec_count(), 2)
  assert_true(spec_has_token(registry, "overlay-kept", "KEPTMARK"))
  assert_true(spec_has_token(registry, "overlay-demo", "OVERLAYMARK"))
  assert_eq(registry.detect_from_path("a/b.okept"), Some("overlay-kept"))
  remove_overlay_tree([
    base + "/kept.kgf",
    base + "/demo.kgf",
    base,
    overlay + "/demo.kgf",
    overlay,
    root,
  ])
}

///|
test "registry: load_from_dirs records each spec's origin path" {
  let root = overlay_temp_root("registry-overlay-origin-")
  let base = root + "/base"
  let overlay = root + "/overlay"
  write_overlay_spec(base, "kept.kgf", "overlay-kept", ".okept", "KEPTMARK")
  write_overlay_spec(base, "demo.kgf", "overlay-demo", ".odemo", "BASEMARK")
  write_overlay_spec(
    overlay, "demo.kgf", "overlay-demo", ".odemo", "OVERLAYMARK",
  )
  let registry = KGFRegistry::load_from_dirs([base, overlay])
  assert_eq(
    registry.get_spec_origin("overlay-demo"),
    Some(overlay + "/demo.kgf"),
  )
  assert_eq(registry.get_spec_origin("overlay-kept"), Some(base + "/kept.kgf"))
  assert_eq(registry.get_spec_origin("not-registered"), None)
  assert_eq(registry.get_layer_roots(), [base, overlay])
  remove_overlay_tree([
    base + "/kept.kgf",
    base + "/demo.kgf",
    base,
    overlay + "/demo.kgf",
    overlay,
    root,
  ])
}

///|
test "registry: layer order decides the winner" {
  let root = overlay_temp_root("registry-overlay-order-")
  let base = root + "/base"
  let overlay = root + "/overlay"
  write_overlay_spec(base, "demo.kgf", "overlay-demo", ".odemo", "BASEMARK")
  write_overlay_spec(
    overlay, "demo.kgf", "overlay-demo", ".odemo", "OVERLAYMARK",
  )
  // Reversing the chain reverses the winner: the rule is purely positional.
  let reversed = KGFRegistry::load_from_dirs([overlay, base])
  assert_true(spec_has_token(reversed, "overlay-demo", "BASEMARK"))
  assert_eq(reversed.get_spec_origin("overlay-demo"), Some(base + "/demo.kgf"))
  assert_eq(reversed.get_layer_roots(), [overlay, base])
  remove_overlay_tree([
    base + "/demo.kgf",
    base,
    overlay + "/demo.kgf",
    overlay,
    root,
  ])
}

///|
test "registry: load_from_dir is the single-directory case of load_from_dirs" {
  let root = overlay_temp_root("registry-overlay-single-")
  let base = root + "/base"
  write_overlay_spec(base, "demo.kgf", "overlay-demo", ".odemo", "BASEMARK")
  let one = KGFRegistry::load_from_dir(base)
  let many = KGFRegistry::load_from_dirs([base])
  assert_eq(one.spec_count(), many.spec_count())
  assert_eq(one.get_layer_roots(), [base])
  assert_eq(one.get_spec_origin("overlay-demo"), Some(base + "/demo.kgf"))
  remove_overlay_tree([base + "/demo.kgf", base, root])
}

///|
test "registry: a missing directory in the chain is skipped, not fatal" {
  let root = overlay_temp_root("registry-overlay-absent-")
  let base = root + "/base"
  write_overlay_spec(base, "demo.kgf", "overlay-demo", ".odemo", "BASEMARK")
  let registry = KGFRegistry::load_from_dirs([base, root + "/__missing__"])
  assert_eq(registry.spec_count(), 1)
  assert_true(spec_has_token(registry, "overlay-demo", "BASEMARK"))
  remove_overlay_tree([base + "/demo.kgf", base, root])
}
