///|
test "solid: parse_args splits comma-separated source directories via common parser" {
  let config = parse_args(["--from=apps/web, apps/admin ,pkg/shared"], 0)
  assert_eq(config.from_dirs, ["apps/web", "apps/admin", "pkg/shared"])
}

///|
test "solid: categorize_matches uses shared path scope matching" {
  let matches : Array[FileMatch] = [
    {
      _source1: "web:src/http/api.ts",
      _source2: "admin:src/http/api.ts",
      similarity: 1.0,
      relative_path: "src/http/api.ts",
      _matched_rule: None,
    },
  ]
  let rules : Array[SolidRule] = [
    { pattern: "src/**/api.[tj]s", target: "shared/http/" },
  ]
  let categorized = categorize_matches(matches, rules, "components")
  assert_eq(categorized.unmatched.length(), 0)
  assert_true(categorized.by_target.get("components/shared/http/") is Some(_))
}
