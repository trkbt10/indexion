// Tests for template processing functions.

///|
test "process_template replaces single placeholder" {
  let template = "Before\n<!-- AUTO:TEST -->old<!-- /AUTO:TEST -->\nAfter"
  let placeholders : Map[String, String] = {}
  placeholders.set("TEST", "new content\n")
  let result = process_template(template, placeholders)
  assert_true(find_string(result, "new content") >= 0)
  assert_true(find_string(result, "old") < 0)
}

///|
test "process_template replaces multiple placeholders" {
  let template = "<!-- AUTO:A -->a<!-- /AUTO:A -->\n<!-- AUTO:B -->b<!-- /AUTO:B -->"
  let placeholders : Map[String, String] = {}
  placeholders.set("A", "alpha\n")
  placeholders.set("B", "beta\n")
  let result = process_template(template, placeholders)
  assert_true(find_string(result, "alpha") >= 0)
  assert_true(find_string(result, "beta") >= 0)
}

///|
test "process_template preserves unmatched placeholders" {
  let template = "<!-- AUTO:MISSING -->content<!-- /AUTO:MISSING -->"
  let placeholders : Map[String, String] = {}
  let result = process_template(template, placeholders)
  assert_true(find_string(result, "content") >= 0)
}

///|
test "process_template handles empty placeholders" {
  let template = "<!-- AUTO:TEST -->old<!-- /AUTO:TEST -->"
  let placeholders : Map[String, String] = {}
  placeholders.set("TEST", "")
  let result = process_template(template, placeholders)
  assert_true(find_string(result, "old") < 0)
}

///|
test "process_template handles no placeholders" {
  let template = "No placeholders here"
  let placeholders : Map[String, String] = {}
  placeholders.set("TEST", "value")
  let result = process_template(template, placeholders)
  assert_eq(result, template)
}

///|
test "find_string finds substring" {
  assert_eq(find_string("hello world", "world"), 6)
  assert_eq(find_string("hello world", "hello"), 0)
  assert_eq(find_string("hello world", "xyz"), -1)
}

///|
test "find_string_from finds from position" {
  assert_eq(find_string_from("hello hello", "hello", 1), 6)
  assert_eq(find_string_from("hello hello", "hello", 7), -1)
}

///|
test "substring extracts correctly" {
  assert_eq(substring("hello world", 0, 5), "hello")
  assert_eq(substring("hello world", 6, 11), "world")
  assert_eq(substring("hello", 0, 100), "hello")
}

///|
test "substring_from extracts to end" {
  assert_eq(substring_from("hello world", 6), "world")
  assert_eq(substring_from("hello", 0), "hello")
}

///|
test "extract_placeholders finds all names" {
  let template = "<!-- AUTO:A -->x<!-- /AUTO:A -->\n<!-- AUTO:B -->y<!-- /AUTO:B -->"
  let names = extract_placeholders(template)
  assert_eq(names.length(), 2)
  assert_true(array_contains(names, "A"))
  assert_true(array_contains(names, "B"))
}

///|
test "extract_placeholders returns empty for no placeholders" {
  let template = "No placeholders here"
  let names = extract_placeholders(template)
  assert_eq(names.length(), 0)
}

///|
test "extract_placeholders deduplicates names" {
  let template = "<!-- AUTO:A -->x<!-- /AUTO:A -->\n<!-- AUTO:A -->y<!-- /AUTO:A -->"
  let names = extract_placeholders(template)
  assert_eq(names.length(), 1)
}

///|
test "validate_placeholders finds missing" {
  let template = "<!-- AUTO:A -->x<!-- /AUTO:A -->\n<!-- AUTO:B -->y<!-- /AUTO:B -->"
  let placeholders : Map[String, String] = {}
  placeholders.set("A", "value")
  let missing = validate_placeholders(template, placeholders)
  assert_eq(missing.length(), 1)
  assert_eq(missing[0], "B")
}

///|
test "validate_placeholders returns empty when all present" {
  let template = "<!-- AUTO:A -->x<!-- /AUTO:A -->"
  let placeholders : Map[String, String] = {}
  placeholders.set("A", "value")
  let missing = validate_placeholders(template, placeholders)
  assert_eq(missing.length(), 0)
}

///|
/// Helper function to check if array contains a value.
fn array_contains(arr : Array[String], value : String) -> Bool {
  for item in arr {
    if item == value {
      return true
    }
  }
  false
}
