// Tests for `extends:` resolution in the registry — the point where a
// derived spec's inherited sections are actually filled in.

///|
/// Build the language-keyed source set that `resolve_spec_source` and
/// `register_spec_sources` work on.
fn sources_by_language(
  texts : Array[String],
) -> (Array[@parser.KGFSpecSource], Map[String, @parser.KGFSpecSource]) {
  let sources : Array[@parser.KGFSpecSource] = []
  let by_language : Map[String, @parser.KGFSpecSource] = Map([])
  for text in texts {
    let source = @parser.parse_kgf_source(text)
    sources.push(source)
    by_language.set(source.get_language(), source)
  }
  (sources, by_language)
}

///|
/// A base spec with every section a derived spec might inherit.
let base_spec_text : String =
  #|kgf 0.6
  #|language: e-base
  #|sources: .ebase
  #|
  #|=== lex
  #|SKIP /\s+/
  #|TOKEN WORD /[a-z]+/
  #|
  #|=== grammar
  #|Doc -> WORD*
  #|
  #|=== features
  #|content_type: document
  #|
  #|=== resolver
  #|exts: .ebase
  #|module_path_style: slash

///|
test "extends: registry resolves a derived spec's inherited sections" {
  let derived_text =
    #|kgf 0.6
    #|language: e-derived
    #|sources: .ederived
    #|extends: e-base
    #|
    #|=== features
    #|content_type: config
  let (sources, _) = sources_by_language([base_spec_text, derived_text])
  let registry = KGFRegistry::new()
  registry.register_spec_sources(sources)
  let derived = registry.get_spec("e-derived").unwrap()
  // Inherited: lex and grammar come from the base and really parse.
  assert_eq(derived.get_tokens().length(), 2)
  assert_true(derived.get_rules().contains("Doc"))
  // Overridden: the derived spec's own features win wholesale.
  assert_eq(derived.get_feature("content_type"), Some(["config"]))
  // Provenance is kept on the resolved spec.
  assert_eq(derived.get_extends(), Some("e-base"))
  // The base itself is unaffected.
  let base = registry.get_spec("e-base").unwrap()
  assert_eq(base.get_feature("content_type"), Some(["document"]))
  assert_true(base.get_extends() is None)
}

///|
test "extends: sources and language are never inherited" {
  let derived_text =
    #|kgf 0.6
    #|language: e-derived
    #|sources: .ederived
    #|extends: e-base
  let no_sources_text =
    #|kgf 0.6
    #|language: e-nosources
    #|extends: e-base
  let (sources, _) = sources_by_language([
    base_spec_text, derived_text, no_sources_text,
  ])
  let registry = KGFRegistry::new()
  registry.register_spec_sources(sources)
  let derived = registry.get_spec("e-derived").unwrap()
  assert_eq(derived.get_language(), "e-derived")
  // The derived spec claims only its own extension — the base's `.ebase`
  // still resolves to the base.
  assert_eq(registry.get_lang_from_ext(".ederived"), Some("e-derived"))
  assert_eq(registry.get_lang_from_ext(".ebase"), Some("e-base"))
  // A derived spec that declares no `sources:` claims no extension, exactly
  // as a standalone spec with no `sources:` would; the base's header is not
  // borrowed. The `exts:` of the inherited `=== resolver` is a resolution
  // setting, not a claim on a file extension.
  let no_sources = registry.get_spec("e-nosources").unwrap()
  assert_eq(no_sources.get_resolver().get_sources(), [])
}

///|
test "extends: a chain takes each section from the nearest ancestor" {
  let mid_text =
    #|kgf 0.6
    #|language: e-mid
    #|sources: .emid
    #|extends: e-base
    #|
    #|=== grammar
    #|Doc -> WORD+
    #|
    #|=== features
    #|content_type: config
  let leaf_text =
    #|kgf 0.6
    #|language: e-leaf
    #|sources: .eleaf
    #|extends: e-mid
    #|
    #|=== features
    #|content_type: code
  let (sources, _) = sources_by_language([base_spec_text, mid_text, leaf_text])
  let registry = KGFRegistry::new()
  registry.register_spec_sources(sources)
  let leaf = registry.get_spec("e-leaf").unwrap()
  // From the leaf itself.
  assert_eq(leaf.get_feature("content_type"), Some(["code"]))
  // From the middle spec, not the base: nearest ancestor wins.
  assert_eq(leaf.get_rule("Doc").unwrap().get_expr(), "WORD+")
  // From the base, two links up.
  assert_eq(leaf.get_tokens().length(), 2)
  assert_eq(leaf.get_resolver().get_module_path_style().as_string(), "slash")
  assert_eq(leaf.get_extends(), Some("e-mid"))
}

///|
test "extends: a declared-but-empty section overrides an inherited one" {
  let derived_text =
    #|kgf 0.6
    #|language: e-derived
    #|sources: .ederived
    #|extends: e-base
    #|
    #|=== grammar
    #|
  let (sources, _) = sources_by_language([base_spec_text, derived_text])
  let registry = KGFRegistry::new()
  registry.register_spec_sources(sources)
  let derived = registry.get_spec("e-derived").unwrap()
  // `=== grammar` is declared, empty: the base's Doc rule must NOT leak in.
  assert_eq(derived.get_rules().length(), 0)
  // Sections the derived spec leaves out are still inherited.
  assert_eq(derived.get_tokens().length(), 2)
}

///|
test "extends: unknown base is an error and leaves own sections in place" {
  let orphan_text =
    #|kgf 0.6
    #|language: e-orphan
    #|sources: .eorphan
    #|extends: e-missing
    #|
    #|=== grammar
    #|Doc -> WORD*
  let (sources, by_language) = sources_by_language([orphan_text])
  let (resolved, error) = resolve_spec_source(sources[0], by_language)
  assert_eq(error, Some(UnknownBase("e-orphan", "e-missing")))
  // Degrading to the spec's own sections keeps loading total; reporting is
  // `kgf check`'s job.
  assert_true(resolved.get_section("grammar") is Some(_))
  assert_true(resolved.get_section("lex") is None)
  let registry = KGFRegistry::new()
  registry.register_spec_sources(sources)
  assert_true(registry.get_spec("e-orphan") is Some(_))
}

///|
test "extends: an empty `extends:` value is an error" {
  let text =
    #|kgf 0.6
    #|language: e-empty
    #|extends:
    #|
    #|=== grammar
    #|Doc -> WORD*
  let (sources, by_language) = sources_by_language([text])
  let (_, error) = resolve_spec_source(sources[0], by_language)
  assert_eq(error, Some(EmptyBase("e-empty")))
}

///|
test "extends: a cycle is reported with the chain that closes it" {
  let a_text =
    #|kgf 0.6
    #|language: e-a
    #|extends: e-b
    #|
    #|=== lex
    #|TOKEN A /a/
  let b_text =
    #|kgf 0.6
    #|language: e-b
    #|extends: e-c
    #|
    #|=== grammar
    #|Doc -> A*
  let c_text =
    #|kgf 0.6
    #|language: e-c
    #|extends: e-a
    #|
    #|=== features
    #|content_type: document
  let (sources, by_language) = sources_by_language([a_text, b_text, c_text])
  let (resolved, error) = resolve_spec_source(sources[0], by_language)
  assert_eq(error, Some(Cycle(["e-a", "e-b", "e-c", "e-a"])))
  // A cycle still produces a usable spec: everything merged before the walk
  // closed on itself.
  assert_true(resolved.get_section("grammar") is Some(_))
  // Loading a cyclic set must terminate rather than hang or overflow.
  let registry = KGFRegistry::new()
  registry.register_spec_sources(sources)
  assert_eq(registry.spec_count(), 3)
}

///|
test "extends: a self-extending spec is a one-step cycle" {
  let text =
    #|kgf 0.6
    #|language: e-self
    #|extends: e-self
    #|
    #|=== lex
    #|TOKEN A /a/
  let (sources, by_language) = sources_by_language([text])
  let (_, error) = resolve_spec_source(sources[0], by_language)
  assert_eq(error, Some(Cycle(["e-self", "e-self"])))
}

///|
test "extends: a spec without `extends:` resolves to itself unchanged" {
  let (sources, by_language) = sources_by_language([base_spec_text])
  let (resolved, error) = resolve_spec_source(sources[0], by_language)
  assert_true(error is None)
  assert_eq(resolved.get_language(), "e-base")
  assert_true(resolved.get_extends() is None)
}

///|
test "extends: resolution does not depend on load order" {
  let derived_text =
    #|kgf 0.6
    #|language: e-derived
    #|sources: .ederived
    #|extends: e-base
  // The base is loaded *after* the spec that extends it, as happens when the
  // base lives in a later subdirectory. Two-phase loading must not care.
  let (sources, _) = sources_by_language([derived_text, base_spec_text])
  let registry = KGFRegistry::new()
  registry.register_spec_sources(sources)
  let derived = registry.get_spec("e-derived").unwrap()
  assert_eq(derived.get_tokens().length(), 2)
  assert_true(derived.get_rules().contains("Doc"))
}

///|
test "extends: every shipped spec names a base that exists" {
  let dir = @kgf_fixtures.get_kgfs_dir()
  let is_dir = @fs.is_dir(dir) catch { _ => false }
  if !is_dir {
    return
  }
  let registry = KGFRegistry::load_from_dir(dir)
  for language in registry.get_languages() {
    match registry.get_spec(language).unwrap().get_extends() {
      Some(base) => {
        assert_true(base.length() > 0)
        assert_true(registry.get_spec(base) is Some(_))
      }
      None => ()
    }
  }
}
