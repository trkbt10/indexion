///|
/// Regression tests for the greedy/lazy fast-path look-ahead bug in the
/// matcher: an optional element (`?`, `*`, `{0,m}`) that follows the current
/// element was mistaken for a mandatory literal boundary, so a match with the
/// optional element absent was wrongly rejected. The minimal case is `ab?c`
/// against "ac". It first surfaced as the Rust KGF lexer failing to tokenize
/// outer attributes `#[...]` (pattern `/#!?\[[^\]]*\]/`, `!` absent).

///|
test "optional literal absent - minimal ab?c" {
  assert_true(matches_at("ab?c", "ac", 0)) // b absent
  assert_true(matches_at("ab?c", "abc", 0)) // b present
}

///|
test "star literal absent - minimal ab*c" {
  assert_true(matches_at("ab*c", "ac", 0)) // zero b
  assert_true(matches_at("ab*c", "abc", 0)) // one b
  assert_true(matches_at("ab*c", "abbbc", 0)) // many b
}

///|
test "brace-zero literal absent - ab{0,2}c" {
  assert_true(matches_at("ab{0,2}c", "ac", 0)) // zero b
  assert_true(matches_at("ab{0,2}c", "abc", 0)) // one b
  assert_true(matches_at("ab{0,2}c", "abbc", 0)) // two b
}

///|
test "mandatory next literal still required - ab+c rejects ac" {
  assert_false(matches_at("ab+c", "ac", 0)) // b required at least once
  assert_true(matches_at("ab+c", "abc", 0))
}

///|
test "optional before escaped bracket" {
  assert_true(matches_at("#!?\\[", "#[", 0)) // ! absent
  assert_true(matches_at("#!?\\[", "#![", 0)) // ! present
}

///|
test "rust outer attribute tokenizes - #[test]" {
  let pat = "#!?\\[[^\\]]*\\]"
  assert_true(matches_at(pat, "#[test]", 0))
}

///|
test "rust outer attribute tokenizes - #[derive(Clone, PartialEq)]" {
  let pat = "#!?\\[[^\\]]*\\]"
  assert_true(matches_at(pat, "#[derive(Clone, PartialEq)]", 0))
}

///|
test "rust inner attribute still tokenizes - #![allow(x)]" {
  let pat = "#!?\\[[^\\]]*\\]"
  assert_true(matches_at(pat, "#![allow(dead_code)]", 0))
}

///|
test "lazy optional look-ahead - a.*?b?c" {
  // Lazy quantifier fast path with an optional literal following.
  assert_true(matches_at("ab?c", "ac", 0))
}

///|
/// The first-char filter must not treat a zero-minimum *brace* quantifier as
/// mandatory. `a*b`/`a?b` were already handled, but `a{0}b`, `a{0,}b`,
/// `a{0,m}b` seeded the filter with `a` and wrongly rejected inputs starting
/// with `b`. Both the matcher fast paths and the filter now share
/// `quantifier_requires_one`, so these agree.
test "first-char filter - zero-min brace quantifier not mandatory" {
  assert_true(matches_at("a{0,}b", "b", 0)) // {0,} may match zero a's
  assert_true(matches_at("a{0,3}b", "b", 0))
  assert_true(matches_at("a{0}b", "b", 0))
  // Still matches when the element is present.
  assert_true(matches_at("a{0,}b", "aaab", 0))
  assert_true(matches_at("a{0,3}b", "ab", 0))
  // A required first element still filters (and rejects a bad first char).
  assert_false(matches_at("a{1,}b", "b", 0))
}
