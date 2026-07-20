///|
/// Tests for YAML frontmatter emission.

///|
test "plain scalars stay unquoted" {
  let out = render_frontmatter([
    ("type", Str("Package")),
    ("title", Str("src/config")),
  ])
  assert_eq(out, "---\ntype: Package\ntitle: src/config\n---\n")
}

///|
test "scalars with yaml indicators are quoted and escaped" {
  let out = render_frontmatter([
    ("description", Str("Has: colon")),
    ("note", Str("quote \" and backslash \\")),
  ])
  assert_eq(
    out, "---\ndescription: \"Has: colon\"\nnote: \"quote \\\" and backslash \\\\\"\n---\n",
  )
}

///|
test "empty scalar is quoted" {
  let out = render_frontmatter([("description", Str(""))])
  assert_eq(out, "---\ndescription: \"\"\n---\n")
}

///|
test "leading indicator chars force quoting" {
  let out = render_frontmatter([("title", Str("-leading"))])
  assert_eq(out, "---\ntitle: \"-leading\"\n---\n")
}

///|
test "lists render in flow style with per-item quoting" {
  let out = render_frontmatter([("tags", List(["alpha", "b:c"]))])
  assert_eq(out, "---\ntags: [alpha, \"b:c\"]\n---\n")
}

///|
test "timestamp with colons is quoted" {
  let out = render_frontmatter([("timestamp", Str("2026-07-20T00:00:00Z"))])
  assert_eq(out, "---\ntimestamp: \"2026-07-20T00:00:00Z\"\n---\n")
}

///|
test "yaml-coercible scalars are quoted" {
  let out = render_frontmatter([
    ("a", Str("true")),
    ("b", Str("False")),
    ("c", Str("null")),
    ("d", Str("123")),
    ("e", Str("1.5")),
    ("f", Str("~")),
  ])
  assert_eq(
    out, "---\na: \"true\"\nb: \"False\"\nc: \"null\"\nd: \"123\"\ne: \"1.5\"\nf: \"~\"\n---\n",
  )
}
