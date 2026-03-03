// Tests for shared CLI utilities.

///|
test "get_arg_value: extracts value after position" {
  assert_eq(get_arg_value("--type=deps", 7), "deps")
  assert_eq(get_arg_value("--output=out.md", 9), "out.md")
}

///|
test "get_arg_value: returns empty when at end" {
  assert_eq(get_arg_value("--type=", 7), "")
}

///|
test "get_arg_value: returns empty when beyond length" {
  assert_eq(get_arg_value("abc", 10), "")
}

///|
test "get_arg_value: handles single char value" {
  assert_eq(get_arg_value("--x=y", 4), "y")
}

///|
test "trim_trailing_slash: removes trailing slash" {
  assert_eq(trim_trailing_slash("src/"), "src")
  assert_eq(trim_trailing_slash("path/to/dir/"), "path/to/dir")
}

///|
test "trim_trailing_slash: no change without slash" {
  assert_eq(trim_trailing_slash("src"), "src")
  assert_eq(trim_trailing_slash("path/to/dir"), "path/to/dir")
}

///|
test "trim_trailing_slash: empty string unchanged" {
  assert_eq(trim_trailing_slash(""), "")
}

///|
test "is_supported_file: recognizes TypeScript" {
  assert_true(is_supported_file("src/main.ts"))
  assert_true(is_supported_file("component.tsx"))
}

///|
test "is_supported_file: recognizes JavaScript" {
  assert_true(is_supported_file("app.js"))
  assert_true(is_supported_file("utils.jsx"))
  assert_true(is_supported_file("config.mjs"))
}

///|
test "is_supported_file: recognizes MoonBit" {
  assert_true(is_supported_file("src/main.mbt"))
}

///|
test "is_supported_file: recognizes Python" {
  assert_true(is_supported_file("script.py"))
}

///|
test "is_supported_file: recognizes other languages" {
  assert_true(is_supported_file("main.go"))
  assert_true(is_supported_file("lib.rs"))
  assert_true(is_supported_file("schema.sql"))
}

///|
test "is_supported_file: recognizes web files" {
  assert_true(is_supported_file("index.html"))
  assert_true(is_supported_file("style.css"))
  assert_true(is_supported_file("README.md"))
}

///|
test "is_supported_file: rejects unsupported extensions" {
  assert_false(is_supported_file("image.png"))
  assert_false(is_supported_file("data.json"))
  assert_false(is_supported_file("config.yaml"))
  assert_false(is_supported_file("binary.exe"))
}

///|
test "join_lines: joins with newlines" {
  let lines = ["line1", "line2", "line3"]
  assert_eq(join_lines(lines), "line1\nline2\nline3")
}

///|
test "join_lines: single line no newline" {
  let lines = ["only"]
  assert_eq(join_lines(lines), "only")
}

///|
test "join_lines: empty returns empty" {
  let lines : Array[String] = []
  assert_eq(join_lines(lines), "")
}

///|
test "join_lines: handles empty strings" {
  let lines = ["a", "", "b"]
  assert_eq(join_lines(lines), "a\n\nb")
}
