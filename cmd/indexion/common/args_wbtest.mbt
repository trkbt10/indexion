///|
test "common: parse_comma_list trims entries but preserves internal spaces" {
  assert_eq(parse_comma_list("apps/web, apps/admin ,pkg/shared assets"), [
    "apps/web", "apps/admin", "pkg/shared assets",
  ])
}

///|
test "common: parse_comma_list skips empty entries" {
  assert_eq(parse_comma_list("foo,, bar, "), ["foo", "bar"])
}
