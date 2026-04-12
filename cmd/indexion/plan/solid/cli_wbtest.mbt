///|
test "solid: from_matches splits comma-separated source directories via common parser" {
  let cmd = command()
  let matches = cmd.parse(argv=["--from=apps/web, apps/admin ,pkg/shared"][:])
  let config = SolidConfig::from_matches(matches)
  assert_eq(config.from_dirs, ["apps/web", "apps/admin", "pkg/shared"])
}

///|
test "solid: categorize_matches uses shared path scope matching" {
  let matches : Array[FileMatch] = [
    {
      source1: "web:src/http/api.ts",
      source2: "admin:src/http/api.ts",
      similarity: 1.0,
      relative_path: "src/http/api.ts",
      matched_rule: None,
      match_kind: PathMatch,
    },
  ]
  let rules : Array[SolidRule] = [
    { pattern: "src/**/api.[tj]s", target: "shared/http/" },
  ]
  let categorized = categorize_matches(matches, rules, "components")
  assert_eq(categorized.unmatched.length(), 0)
  assert_true(categorized.by_target.get("components/shared/http/") is Some(_))
}

///|
test "solid: content matches are categorized correctly" {
  let matches : Array[FileMatch] = [
    {
      source1: "web:src/auth/login.ts",
      source2: "admin:src/auth/signin.ts",
      similarity: 0.85,
      relative_path: "src/auth/login.ts",
      matched_rule: None,
      match_kind: ContentMatch,
    },
  ]
  let rules : Array[SolidRule] = [
    { pattern: "src/auth/**", target: "shared/auth/" },
  ]
  let categorized = categorize_matches(matches, rules, "components")
  assert_eq(categorized.unmatched.length(), 0)
  assert_true(categorized.by_target.get("components/shared/auth/") is Some(_))
}

///|
test "solid: build_extraction_tasks groups functions by name" {
  let func_matches : Array[CrossFunctionMatch] = [
    {
      func_name1: "validate",
      func_name2: "validate",
      file1: "web:src/auth.mbt",
      file2: "admin:src/auth.mbt",
      dir1: "web",
      dir2: "admin",
      similarity: 0.95,
      body_preview: "fn validate() { ... }",
      line_count: 10,
    },
    {
      func_name1: "hash_password",
      func_name2: "hash_password",
      file1: "web:src/auth.mbt",
      file2: "admin:src/auth.mbt",
      dir1: "web",
      dir2: "admin",
      similarity: 1.0,
      body_preview: "fn hash_password() { ... }",
      line_count: 5,
    },
  ]
  let rules : Array[SolidRule] = []
  let tasks = build_extraction_tasks(func_matches, rules, "shared")
  // Should create 2 tasks (one per function group)
  assert_eq(tasks.length(), 2)
  // First task should be the higher-confidence one (hash_password at 1.0)
  assert_eq(tasks[0].confidence, 1.0)
  assert_eq(tasks[0].merge_strategy, "copy")
  // Second task should be the lower one (validate at 0.95)
  assert_eq(tasks[1].confidence, 0.95)
  assert_eq(tasks[1].merge_strategy, "reconcile")
}
