///|
test "agent orient: readiness quiz captures owner and forbidden path" {
  let quiz = readiness_quiz(
    [{ path: "src/identity", reason: "owner", }],
    [],
    [{ path: "cmd/indexion/identity/cli.mbt", reason: "consumer", }],
    [{ path: "cmd/indexion/identity/cli.mbt", reason: "forbidden", }],
    [{ path: "src/identity/audit.mbt", reason: "read first", }],
  )
  assert_eq(quiz.length(), 3)
  assert_eq(quiz[0].expected_answer, "src/identity")
  assert_eq(quiz[1].expected_answer, "cmd/indexion/identity/cli.mbt")
  assert_eq(quiz[2].expected_answer, "src/identity/audit.mbt")
}

///|
test "agent orient: readiness quiz prefers implementation preflight evidence" {
  let quiz = readiness_quiz(
    [{ path: "src/identity", reason: "owner", }],
    [],
    [],
    [{ path: "cmd/indexion/identity/cli.mbt", reason: "forbidden", }],
    [
      { path: "cmd/indexion/main.mbt", reason: "consumer read first", },
      { path: "src/identity/audit.mbt", reason: "read second", },
    ],
  )
  assert_eq(quiz[2].expected_answer, "src/identity/audit.mbt")
}

///|
test "agent orient: consumer dominated terms are not owner query terms" {
  let briefs : Array[LocalFileBrief] = [
    new_local_file_brief(
      "cmd/indexion/main.mbt",
      "h1",
      "cmd indexion cli",
      "cmd indexion cli",
      role="cli-consumer",
    ),
    new_local_file_brief(
      "cmd/indexion/identity/cli.mbt",
      "h2",
      "identity cli",
      "identity cli",
      role="cli-consumer",
    ),
    new_local_file_brief(
      "skills/skills/indexion-identity/SKILL.md",
      "h3",
      "identity cli",
      "identity cli",
      role="consumer",
    ),
    new_local_file_brief(
      "src/identity/audit.mbt", "h4", "identity audit", "identity audit",
    ),
  ]
  assert_true(is_consumer_dominated_term("cli", briefs))
  assert_false(is_consumer_dominated_term("identity", briefs))
}
