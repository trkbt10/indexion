///|
test "PathSubject::new keeps canonical path first and deduplicates alternatives" {
  let subject = PathSubject::new("docs/api.md", additional_paths=[
    "docs/api.md", "/tmp/project/docs/api.md",
  ])
  assert_eq(subject.candidate_paths, ["docs/api.md", "/tmp/project/docs/api.md"])
}

///|
test "subject_matches_pattern checks alternate path spellings" {
  let subject = PathSubject::new("README.md", additional_paths=[
    "docs/reference/README.md",
  ])
  assert_true(subject_matches_pattern(subject, "docs/**/*.md"))
}

///|
test "PathScope: include and exclude patterns share matcher semantics" {
  let scope = PathScope::new(includes=["src/**/api.[tj]s"], excludes=[
    "**/legacy/**",
  ])
  assert_true(scope.matches_path("src/http/api.ts"))
  assert_false(scope.matches_path("src/legacy/api.ts"))
  assert_false(scope.matches_path("src/http/api.py"))
}
