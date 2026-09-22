///|
test "agent orient: preflight leads with initial owner evidence" {
  let briefs : Array[LocalFileBrief] = [
    new_local_file_brief(
      "skills/skills/indexion-agent-orient/SKILL.md",
      "h1",
      "agent orient thin cli reconcile search graph",
      "Agent orientation skill tells consumers to run graph search and reconcile before editing CLI.",
      role="consumer",
    ),
    new_local_file_brief(
      "src/identity/README.md",
      "h2",
      "identity name content drift",
      "Names and content drift apart. Identity scores whether names still fit implementation contents.",
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
  let task = "name/content drift scoring"
  let terms = owner_task_terms_from_map(task_tokens(task), map)
  let owners = likely_owners(map, terms, task, 2)
  assert_eq(owners[0].path, "src/identity")
  assert_true(
    owners[0].reason.contains("Initial implementation-owner hypothesis"),
  )
  let scored = score_briefs(briefs, task_tokens(task), task)
  scored.sort_by(fn(a, b) { b.score.compare(a.score) })
  let preflight = required_preflight(map, owners, scored, 3)
  assert_eq(preflight[0].path, "src/identity/README.md")
  assert_true(preflight[0].reason.contains("confirm the likely owner"))
}

///|
fn owner_path_exists(map : AgentOrientMap, path : String) -> Bool {
  for owner in map.owners {
    if owner.path == path {
      return true
    }
  }
  false
}
