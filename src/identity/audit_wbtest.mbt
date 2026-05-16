///|
using @test {assert_eq}

test "identity audit: file names are scoped by parent directory" {
  let model : PathNameModel = {
    basename_counts: { "main.mbt": 2, "unique.mbt": 1 },
  }
  assert_eq(scoped_path_name("src/a/main.mbt", model), "a main")
  assert_eq(scoped_path_name("src/b/main.mbt", model), "b main")
  assert_eq(scoped_path_name("src/a/unique.mbt", model), "a unique")
}

///|
test "identity audit: path scope terms are derived from path structure" {
  let terms = path_scope_terms("cmd/indexion/identity/cli.mbt")
  assert_true(terms.contains("cmd"))
  assert_true(terms.contains("indexion"))
  assert_true(terms.contains("identity"))
  assert_true(terms.contains("cli"))
}

///|
test "identity audit: declaration-heavy files are insufficient content" {
  let entity : LocalEntitySummary = {
    kind: "file",
    path: "src/example/config.mbt",
    origin_hint: "src/example/config.mbt",
    name: "example config",
    actual_summary: "Config path threshold default",
    declaration_symbols: 2,
    behavior_symbols: 1,
  }
  let report : NameDivergence = {
    entity: NamedEntity::new(
      name=Name::single("example config"),
      content="path threshold default",
      origin="src/example/config.mbt",
    ),
    name_in_content_score: 0.0,
    content_breadth: 0.9,
    prominent_unused: ["path", "threshold"],
    action: Split,
    rationale: "test",
  }
  assert_eq(effective_identity_action(entity, report), Hollow)
}

///|
test "identity audit: behavior files keep their reconcile action" {
  let entity : LocalEntitySummary = {
    kind: "file",
    path: "src/example/render.mbt",
    origin_hint: "src/example/render.mbt",
    name: "example render",
    actual_summary: "render write format output",
    declaration_symbols: 0,
    behavior_symbols: 3,
  }
  let report : NameDivergence = {
    entity: NamedEntity::new(
      name=Name::single("example render"),
      content="write format output",
      origin="src/example/render.mbt",
    ),
    name_in_content_score: 0.0,
    content_breadth: 0.9,
    prominent_unused: ["write", "format"],
    action: Split,
    rationale: "test",
  }
  assert_eq(effective_identity_action(entity, report), Split)
}
