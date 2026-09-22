// Tests for the `extends:` header field and the raw-section form
// (`KGFSpecSource`) that spec inheritance is merged in.

///|
test "extends: absent header field yields None" {
  let text =
    #|kgf 0.6
    #|language: markdown
    #|sources: .md
    #|
    #|=== lex
    #|TOKEN TEXT /[^\s]+/
  let header = parse_kgf_header(text)
  assert_eq(header.get_language(), "markdown")
  assert_true(header.get_extends() is None)
  assert_true(parse_kgf_source(text).get_extends() is None)
  assert_true(parse_kgf(text).unwrap().get_extends() is None)
}

///|
test "extends: header field is parsed and reaches the spec" {
  let text =
    #|kgf 0.6
    #|language: sdd-user-story
    #|sources: .md
    #|extends: markdown
    #|
    #|=== features
    #|detection_scope: overlay
  let header = parse_kgf_header(text)
  assert_eq(header.get_language(), "sdd-user-story")
  assert_eq(header.get_sources(), [".md"])
  assert_eq(header.get_extends(), Some("markdown"))
  assert_eq(parse_kgf_source(text).get_extends(), Some("markdown"))
  assert_eq(parse_kgf(text).unwrap().get_extends(), Some("markdown"))
}

///|
test "extends: header field order does not matter" {
  let text =
    #|kgf 0.6
    #|extends: toml
    #|language: cargo-toml
    #|sources: Cargo.toml
    #|
    #|=== grammar
    #|Doc -> Item*
  let header = parse_kgf_header(text)
  assert_eq(header.get_language(), "cargo-toml")
  assert_eq(header.get_extends(), Some("toml"))
  assert_eq(header.get_sources(), ["Cargo.toml"])
}

///|
test "extends: empty value is reported as declared-but-empty" {
  let text =
    #|kgf 0.6
    #|language: broken
    #|extends:
    #|
    #|=== lex
    #|TOKEN TEXT /./
  // Some("") rather than None: an `extends:` with nothing after it is an
  // authoring error the registry and `kgf check` must be able to name,
  // not an absent field.
  assert_eq(parse_kgf_header(text).get_extends(), Some(""))
}

///|
test "extends: a `extends:` inside a section body is not a header field" {
  let text =
    #|kgf 0.6
    #|language: standalone
    #|
    #|=== semantics
    #|on Rule {
    #|  note extends: payload obj("x", 1)
    #|}
  assert_true(parse_kgf_header(text).get_extends() is None)
}

///|
test "spec source: declared-but-empty section differs from absent" {
  let text =
    #|kgf 0.6
    #|language: toml
    #|
    #|=== grammar
    #|Doc -> Item*
    #|
    #|=== semantics
    #|
  let source = parse_kgf_source(text)
  // `=== semantics` is declared with an empty body — a deliberate "no
  // semantics" that must override an inherited section rather than be
  // filled in by it.
  assert_true(source.get_section("semantics") is Some(_))
  assert_true(source.get_section("classify") is None)
}

///|
test "spec source: merge_onto takes undeclared sections from the base" {
  let base_text =
    #|kgf 0.6
    #|language: base
    #|sources: .base
    #|
    #|=== lex
    #|TOKEN A /a/
    #|
    #|=== grammar
    #|Doc -> A*
    #|
    #|=== resolver
    #|module_path_style: slash
  let derived_text =
    #|kgf 0.6
    #|language: derived
    #|sources: .derived
    #|extends: base
    #|
    #|=== grammar
    #|Doc -> A+
  let base = parse_kgf_source(base_text)
  let derived = parse_kgf_source(derived_text)
  let merged = derived.merge_onto(base)
  // Own section wins whole.
  assert_eq(merged.get_section("grammar"), derived.get_section("grammar"))
  // Undeclared sections come from the base.
  assert_eq(merged.get_section("lex"), base.get_section("lex"))
  assert_eq(merged.get_section("resolver"), base.get_section("resolver"))
  // Identity fields are never inherited.
  assert_eq(merged.get_language(), "derived")
  assert_eq(merged.get_sources(), [".derived"])
  assert_eq(merged.get_extends(), Some("base"))
}

///|
test "spec source: to_spec parses the merged sections" {
  let base_text =
    #|kgf 0.6
    #|language: base
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN WORD /[a-z]+/
    #|
    #|=== grammar
    #|Doc -> WORD*
  let derived_text =
    #|kgf 0.6
    #|language: derived
    #|sources: .d
    #|extends: base
    #|
    #|=== features
    #|content_type: document
  let base = parse_kgf_source(base_text)
  let derived = parse_kgf_source(derived_text)
  let spec = derived.merge_onto(base).to_spec()
  assert_eq(spec.get_language(), "derived")
  assert_eq(spec.get_extends(), Some("base"))
  // Inherited lex + grammar are really usable, not just stored text.
  // Two token defs: the SKIP rule and TOKEN WORD.
  assert_eq(spec.get_tokens().length(), 2)
  assert_true(spec.get_rules().contains("Doc"))
  // Own features win; the base declared none.
  assert_eq(spec.get_feature("content_type"), Some(["document"]))
  assert_eq(spec.get_resolver().get_sources(), [".d"])
}
