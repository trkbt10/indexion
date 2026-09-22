///|
test "agent orient: owner query uses provided objective gloss" {
  let briefs : Array[LocalFileBrief] = [
    new_local_file_brief(
      "src/search/README.md",
      "h1",
      "search grep graph wiki reconcile cli",
      "Search infrastructure indexes graph, grep, wiki, and reconcile corpora for codebase lookup.",
      role="documentation",
    ),
    new_local_file_brief(
      "src/identity/README.md",
      "h2",
      "identity name content drift",
      "Names and content are separate artifacts that drift. This package scores whether implementation contents still fit file, folder, and function names.",
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
  let task = "name/content drift scoring and remediation planning"
  let terms = owner_task_terms_from_map(task_tokens(task), map)
  assert_true(terms.contains("content"))
  let owners = likely_owners(map, terms, task, 2)
  if owners[0].path != "src/identity" {
    fail("gloss terms=" + terms.join(",") + " owner=" + owners[0].path)
  }
}

///|
test "agent orient: documentation-only paths remain knowledge sources" {
  let briefs : Array[LocalFileBrief] = [
    new_local_file_brief(
      "RELEASE_NOTES.md",
      "h1",
      "name content drift scoring planning",
      "Release notes mention name/content drift scoring and remediation planning.",
      role="documentation",
    ),
    new_local_file_brief(
      "wiki/Home.md",
      "h2",
      "name content drift scoring planning",
      "Wiki overview mentions name/content drift scoring and remediation planning.",
      role="documentation",
    ),
    new_local_file_brief(
      "src/identity/README.md",
      "h3",
      "identity name content drift",
      "Names and content drift apart. Identity scores whether implementation contents still fit names.",
      role="documentation",
    ),
    new_local_file_brief(
      "src/identity/types.mbt", "h4", "NameDivergence NamedEntity content name drift",
      "NameDivergence measures whether names still fit content bodies",
    ),
  ]
  let map = build_or_update_orient_map(
    { ..AgentOrientConfig::default(), no_update: false, },
    briefs,
    None,
  )
  assert_true(owner_path_exists(map, "RELEASE_NOTES.md"))
  assert_true(owner_path_exists(map, "wiki"))
  let task = "name/content drift scoring and remediation planning"
  let terms = owner_task_terms_from_map(task_tokens(task), map)
  let owners = likely_owners(map, terms, task, 2)
  assert_eq(owners[0].path, "src/identity")
  let knowledge = likely_knowledge_sources(map, terms, task, 2)
  assert_true(
    knowledge[0].path == "RELEASE_NOTES.md" || knowledge[0].path == "wiki",
  )
}
