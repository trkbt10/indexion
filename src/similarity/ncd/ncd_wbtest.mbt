///|
/// Whitebox tests for NCD strategy.

///|
test "NCDStrategy::name returns ncd" {
  let strategy = NCDStrategy::new()
  assert_eq(strategy.name(), "ncd")
}

///|
test "NCDStrategy::distance for identical texts is low" {
  let strategy = NCDStrategy::new()
  let dist = strategy.distance("hello world", "hello world")
  // NCD for identical texts should be relatively low
  assert_true(dist < 0.5)
}

///|
test "NCDStrategy::distance for similar texts is moderate" {
  let strategy = NCDStrategy::new()
  let dist = strategy.distance("hello world", "hello there")
  assert_true(dist > 0.0)
  assert_true(dist < 1.0)
}

///|
test "NCDStrategy::distance for different texts is higher" {
  let strategy = NCDStrategy::new()
  let similar = strategy.distance("hello world", "hello there")
  let different = strategy.distance("hello world", "xyz abc 123 456")
  assert_true(different >= similar)
}

///|
test "NCDStrategy::similarity is 1 - distance" {
  let strategy = NCDStrategy::new()
  let dist = strategy.distance("foo bar", "foo baz")
  let sim = strategy.similarity("foo bar", "foo baz")
  let sum = dist + sim
  assert_true(sum > 0.99 && sum < 1.01)
}

///|
test "calculate_adjacent_ncd returns correct length" {
  let texts = ["a", "b", "c", "d"]
  let result = calculate_adjacent_ncd(texts)
  assert_eq(result.length(), 3)
}
