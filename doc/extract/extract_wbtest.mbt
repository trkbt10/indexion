// Tests for comment extraction functions.

///|
test "parse_doc_comment extracts @file tag" {
  let content =
    #|/**
    #| * @file MyComponent - A useful component
    #| */
  let doc = parse_doc_comment(content)
  assert_eq(doc.get_file_tag(), Some("MyComponent - A useful component"))
}

///|
test "parse_doc_comment extracts @description tag" {
  let content =
    #|/**
    #| * @file Test
    #| * @description This is a description.
    #| */
  let doc = parse_doc_comment(content)
  assert_eq(doc.get_description(), Some("This is a description."))
}

///|
test "parse_doc_comment extracts multiline @description" {
  let content =
    #|/**
    #| * @description This is line one.
    #| * This is line two.
    #| */
  let doc = parse_doc_comment(content)
  assert_eq(
    doc.get_description(),
    Some("This is line one. This is line two."),
  )
}

///|
test "parse_doc_comment extracts @example tag" {
  let content =
    #|/**
    #| * @example
    #| * ```tsx
    #| * <MyComponent />
    #| * ```
    #| */
  let doc = parse_doc_comment(content)
  let example = doc.get_example()
  assert_true(example is Some(_))
  let example_content = example.unwrap()
  assert_true(starts_with(example_content, "```tsx"))
}

///|
test "parse_doc_comment handles all tags together" {
  let content =
    #|/**
    #| * @file Button - Interactive button component
    #| * @description A customizable button with various styles.
    #| * Supports multiple sizes and colors.
    #| * @example
    #| * ```tsx
    #| * <Button variant="primary">Click me</Button>
    #| * ```
    #| */
  let doc = parse_doc_comment(content)
  assert_eq(
    doc.get_file_tag(),
    Some("Button - Interactive button component"),
  )
  assert_eq(
    doc.get_description(),
    Some("A customizable button with various styles. Supports multiple sizes and colors."),
  )
  assert_true(doc.get_example() is Some(_))
}

///|
test "parse_doc_comment returns empty doc for no comment" {
  let content = "const x = 1;"
  let doc = parse_doc_comment(content)
  assert_eq(doc.get_file_tag(), None)
  assert_eq(doc.get_description(), None)
  assert_eq(doc.get_example(), None)
}

///|
test "parse_doc_comment handles empty file" {
  let content = ""
  let doc = parse_doc_comment(content)
  assert_eq(doc.get_file_tag(), None)
}

///|
test "parse_doc_comment ignores regular comments" {
  let content =
    #|// This is not JSDoc
    #|/* This is also not JSDoc */
    #|const x = 1;
  let doc = parse_doc_comment(content)
  assert_eq(doc.get_file_tag(), None)
}

///|
test "parse_doc_comment_with_name sets name" {
  let content =
    #|/**
    #| * @file Test component
    #| */
  let doc = parse_doc_comment_with_name(content, "TestComponent")
  assert_eq(doc.get_name(), "TestComponent")
  assert_eq(doc.get_file_tag(), Some("Test component"))
}

///|
test "extract_jsdoc_block finds first JSDoc" {
  let content =
    #|// Comment
    #|/**
    #| * JSDoc here
    #| */
    #|const x = 1;
  let block = extract_jsdoc_block(content)
  assert_true(block is Some(_))
}

///|
test "extract_jsdoc_block returns None for no JSDoc" {
  let content = "const x = 1;"
  let block = extract_jsdoc_block(content)
  assert_true(block is None)
}

///|
test "split_lines splits correctly" {
  let lines = split_lines("a\nb\nc")
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "a")
  assert_eq(lines[1], "b")
  assert_eq(lines[2], "c")
}

///|
test "trim_whitespace removes spaces" {
  assert_eq(trim_whitespace("  hello  "), "hello")
  assert_eq(trim_whitespace("hello"), "hello")
  assert_eq(trim_whitespace("   "), "")
  assert_eq(trim_whitespace(""), "")
}

///|
test "starts_with checks prefix" {
  assert_true(starts_with("hello world", "hello"))
  assert_true(starts_with("hello", "hello"))
  assert_false(starts_with("hello", "world"))
  assert_false(starts_with("hi", "hello"))
}

///|
test "join_strings joins correctly" {
  let strings = ["a", "b", "c"]
  assert_eq(join_strings(strings, ", "), "a, b, c")
  assert_eq(join_strings(strings, ""), "abc")
  assert_eq(join_strings([], ", "), "")
}
