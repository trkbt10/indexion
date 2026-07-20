///|
/// Tests for OKF assembly helpers.

///|
test "resolve_internal_target picks the longest suffix match" {
  let paths : Array[(String, String)] = [
    ("src/kgf", "src/kgf"),
    ("src/kgf/parser", "src/kgf/parser"),
  ]
  assert_eq(
    resolve_internal_target("acme/tool/src/kgf/parser", paths),
    Some("src/kgf/parser"),
  )
  assert_eq(resolve_internal_target("src/kgf", paths), Some("src/kgf"))
  assert_eq(resolve_internal_target("unrelated/pkg", paths), None)
}

///|
test "resolve_internal_target requires a segment boundary" {
  let paths : Array[(String, String)] = [("src/kgf", "src/kgf")]
  // "notsrc/kgf" ends with "src/kgf" but only via "/"-suffix matching,
  // which is a legitimate boundary; "xsrc/kgf" without the separator is not.
  assert_eq(resolve_internal_target("not/src/kgf", paths), Some("src/kgf"))
  assert_eq(resolve_internal_target("xsrc/kgf", paths), None)
}

///|
test "strip_external_prefix strips resolver prefixes" {
  assert_eq(strip_external_prefix("pkg:acme/util", ["pkg:"]), Some("acme/util"))
  assert_eq(strip_external_prefix("pkg:acme/util", ["pkg"]), Some("acme/util"))
  assert_eq(strip_external_prefix("acme/util", ["pkg:"]), None)
  assert_eq(
    strip_external_prefix("npm:left-pad", ["pkg:", "npm:"]),
    Some("left-pad"),
  )
}

///|
test "first_prose_line skips markdown structure" {
  let text = "# Title\n\n- bullet item\n| a | b |\nActual prose here.\nSecond line."
  assert_eq(
    first_prose_line(text, DESCRIPTION_MAX_LENGTH),
    "Actual prose here.",
  )
  assert_eq(first_prose_line("- only\n* bullets", DESCRIPTION_MAX_LENGTH), "")
}

///|
test "exact_package_match requires full-path equality" {
  let paths : Array[(String, String)] = [("src/kgf", "src/kgf")]
  assert_eq(exact_package_match("src/kgf", paths), Some("src/kgf"))
  assert_eq(exact_package_match("./src/kgf", paths), Some("src/kgf"))
  assert_eq(exact_package_match("other/src/kgf", paths), None)
}

///|
test "prose_prefix cuts at the first heading" {
  assert_eq(
    prose_prefix("Intro line.\nMore intro.\n## API\n- item"),
    "Intro line.\nMore intro.",
  )
  assert_eq(prose_prefix("## API\n- item"), "")
}
