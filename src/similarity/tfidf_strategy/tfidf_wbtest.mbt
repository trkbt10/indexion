///|
/// Whitebox tests for TF-IDF strategy.

///|
test "TfidfStrategy::name returns tfidf" {
  let strategy = TfidfStrategy::new()
  assert_eq(strategy.name(), "tfidf")
}

///|
test "TfidfStrategy::similarity is 1 - distance" {
  let strategy = TfidfStrategy::new()
  let dist = strategy.distance("foo bar baz", "foo bar qux")
  let sim = strategy.similarity("foo bar baz", "foo bar qux")
  let sum = dist + sim
  // After KGF migration, string-based distance returns 0.0
  assert_true(sum > 0.99 && sum < 1.01)
}
