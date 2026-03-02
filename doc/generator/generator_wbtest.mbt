// Tests for document generation functions.

///|
test "generate_components_markdown creates heading for each component" {
  let docs = [
    @types.ComponentDoc::make(
      "Button",
      Some("Button component"),
      Some("A clickable button"),
      None,
    ),
    @types.ComponentDoc::make("Input", Some("Input field"), None, None),
  ]
  let result = generate_components_markdown(docs)
  assert_true(contains_string(result, "### Button"))
  assert_true(contains_string(result, "### Input"))
}

///|
test "generate_components_markdown includes description" {
  let docs = [
    @types.ComponentDoc::make(
      "Button",
      None,
      Some("A clickable button"),
      None,
    ),
  ]
  let result = generate_components_markdown(docs)
  assert_true(contains_string(result, "A clickable button"))
}

///|
test "generate_components_markdown uses file_tag when no description" {
  let docs = [
    @types.ComponentDoc::make("Button", Some("Button component"), None, None),
  ]
  let result = generate_components_markdown(docs)
  assert_true(contains_string(result, "Button component"))
}

///|
test "generate_components_markdown includes example" {
  let docs = [
    @types.ComponentDoc::make(
      "Button",
      None,
      None,
      Some("```tsx\n<Button />\n```"),
    ),
  ]
  let result = generate_components_markdown(docs)
  assert_true(contains_string(result, "<Button />"))
}

///|
test "generate_components_markdown handles empty array" {
  let docs : Array[@types.ComponentDoc] = []
  let result = generate_components_markdown(docs)
  assert_eq(result, "")
}

///|
test "generate_components_markdown skips empty names" {
  let docs = [
    @types.ComponentDoc::make("", Some("Empty name"), None, None),
    @types.ComponentDoc::make("Valid", Some("Valid component"), None, None),
  ]
  let result = generate_components_markdown(docs)
  assert_true(contains_string(result, "### Valid"))
  assert_false(contains_string(result, "### \n"))
}

///|
test "generate_tokens_markdown creates table" {
  let tokens = [
    @types.TokenInfo::with_default(
      "spacing-sm",
      "--rei-spacing-sm",
      "Small spacing",
      "4px",
    ),
  ]
  let groups = [@types.TokenGroup::with_tokens("Spacing", "Spacing tokens", tokens)]
  let result = generate_tokens_markdown(groups)
  assert_true(contains_string(result, "### Spacing"))
  assert_true(contains_string(result, "| Token |"))
  assert_true(contains_string(result, "spacing-sm"))
}

///|
test "generate_tokens_markdown includes default values" {
  let tokens = [
    @types.TokenInfo::with_default("size", "--size", "Size", "10px"),
  ]
  let groups = [@types.TokenGroup::with_tokens("Sizes", "Size tokens", tokens)]
  let result = generate_tokens_markdown(groups)
  assert_true(contains_string(result, "| Default |"))
  assert_true(contains_string(result, "`10px`"))
}

///|
test "generate_tokens_markdown omits default column when no defaults" {
  let tokens = [@types.TokenInfo::new("color", "--color", "Color")]
  let groups = [@types.TokenGroup::with_tokens("Colors", "Color tokens", tokens)]
  let result = generate_tokens_markdown(groups)
  assert_false(contains_string(result, "| Default |"))
}

///|
test "generate_tokens_markdown handles empty groups" {
  let groups : Array[@types.TokenGroup] = []
  let result = generate_tokens_markdown(groups)
  assert_eq(result, "")
}

///|
test "generate_component_section includes category header" {
  let docs = [@types.ComponentDoc::make("Button", None, Some("A button"), None)]
  let result = generate_component_section("UI Components", "Basic UI elements", docs)
  assert_true(contains_string(result, "## UI Components"))
  assert_true(contains_string(result, "> Basic UI elements"))
  assert_true(contains_string(result, "### Button"))
}

///|
test "generate_token_category creates category section" {
  let tokens = [@types.TokenInfo::new("color", "--color", "Primary color")]
  let groups = [@types.TokenGroup::with_tokens("Primary", "Primary colors", tokens)]
  let result = generate_token_category(
    "Color Tokens",
    "Theme color variables",
    groups,
  )
  assert_true(contains_string(result, "## Color Tokens"))
  assert_true(contains_string(result, "Theme color variables"))
  assert_true(contains_string(result, "### Primary"))
}

///|
test "generate_import_example creates code block" {
  let result = generate_import_example("Button", "my-lib/Button")
  assert_true(contains_string(result, "```tsx"))
  assert_true(contains_string(result, "import { Button }"))
  assert_true(contains_string(result, "\"my-lib/Button\""))
}

///|
test "join_lines joins correctly" {
  let lines = ["a", "b", "c"]
  let result = join_lines(lines)
  assert_eq(result, "a\nb\nc")
}

///|
test "join_lines handles empty array" {
  let lines : Array[String] = []
  let result = join_lines(lines)
  assert_eq(result, "")
}

///|
/// Helper to check if string contains substring.
fn contains_string(haystack : String, needle : String) -> Bool {
  let h_chars = haystack.to_array()
  let n_chars = needle.to_array()
  let h_len = h_chars.length()
  let n_len = n_chars.length()
  if n_len == 0 {
    return true
  }
  if h_len < n_len {
    return false
  }
  for i = 0; i <= h_len - n_len; i = i + 1 {
    let mut match_ = true
    for j = 0; j < n_len; j = j + 1 {
      if h_chars[i + j] != n_chars[j] {
        match_ = false
        break
      }
    }
    if match_ {
      return true
    }
  }
  false
}
