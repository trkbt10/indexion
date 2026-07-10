// Wbtests for the identity package: name derivation and name ↔ content
// reconcile.

///|
test "name: id and display roles" {
  let n = Name::new(id="dorian-gray", display="Dorian Gray")
  assert_eq(n.get_id(), "dorian-gray")
  assert_eq(n.get_display(), "Dorian Gray")
}

///|
test "name: single value populates both roles" {
  let n = Name::single("README")
  assert_eq(n.get_id(), "README")
  assert_eq(n.get_display(), "README")
}

///|
test "derive_id: empty registry falls back to lowercased input" {
  let registry = @kgf_registry.KGFRegistry::new()
  // No spec available → identifier_kinds set is empty → tokeniser
  // returns nothing → fallback path returns the lowercased input.
  let id = derive_id("Hello World", "spec/x.md", registry)
  // Lowercasing keeps spaces; this is the documented fallback.
  assert_eq(id, "hello world")
}

///|
test "lower_ascii: ASCII letters fold; non-ASCII untouched" {
  assert_eq(lower_ascii("ABC"), "abc")
  assert_eq(lower_ascii("aBc"), "abc")
  // Japanese has no case → unchanged.
  assert_eq(lower_ascii("南京"), "南京")
  // Mixed input.
  assert_eq(lower_ascii("Dorian — 南京"), "dorian — 南京")
}

///|
test "score: empty body is hollow" {
  let entity = NamedEntity::new(
    name=Name::single("Whatever"),
    content="",
    origin="spec/x.md",
  )
  let registry = @kgf_registry.KGFRegistry::new()
  let report = score_name_divergence(entity, registry)
  assert_eq(report.action, Hollow)
}
