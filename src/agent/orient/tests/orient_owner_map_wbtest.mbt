///|
test "agent orient: owner profile uses directory concept text" {
  let briefs : Array[LocalFileBrief] = [
    new_local_file_brief(
      "src/agent/orient/orient.mbt", "h1", "agent orient call implementation should render",
      "agent orient call implementation should render",
    ),
    new_local_file_brief(
      "src/identity/README.md",
      "h2",
      "src identity readme",
      "names and content are separate artifacts that drift; score name content divergence",
      role="documentation",
    ),
    new_local_file_brief(
      "src/identity/types.mbt", "h3", "NameDivergence NamedEntity content name drift",
      "NameDivergence measures whether names still fit content bodies",
    ),
  ]
  let map = build_or_update_orient_map(
    { ..AgentOrientConfig::default(), no_update: false, },
    briefs,
    None,
  )
  let task = "detect drift between names and implementation contents"
  let terms = owner_task_terms_from_map(task_tokens(task), map)
  if !terms.contains("content") {
    fail("profile terms=" + terms.join(","))
  }
  let owners = likely_owners(map, terms, task, 3)
  if owners[0].path != "src/identity" {
    fail("profile terms=" + terms.join(",") + " owner=" + owners[0].path)
  }
}

///|
test "agent orient: wiki sources do not smear parent pages into children" {
  assert_true(source_matches_owner("src/similarity/", "src/similarity"))
  assert_true(
    source_matches_owner(
      "src/similarity/apted/algorithm.mbt", "src/similarity/apted",
    ),
  )
  assert_false(source_matches_owner("src/similarity/", "src/similarity/apted"))
  assert_true(
    wiki_page_is_owner_specific({
      id: "owner",
      title: "Owner",
      file: "owner.md",
      sources: ["src/identity/"],
    }),
  )
  assert_false(
    wiki_page_is_owner_specific({
      id: "hub",
      title: "Hub",
      file: "hub.md",
      sources: ["src/kgf/", "src/core/graph/", "src/digest/"],
    }),
  )
}
