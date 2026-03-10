///|
/// Whitebox tests for Hybrid strategy.

///|
test "HybridStrategy::name returns hybrid" {
  let strategy = HybridStrategy::new()
  assert_eq(strategy.name(), "hybrid")
}

///|
test "HybridStrategy::distance uses NCD" {
  let strategy = HybridStrategy::new()
  let dist = strategy.distance("hello world foo", "hello world bar")
  // Should be between 0 and 1 (NCD only after migration)
  assert_true(dist >= 0.0)
  assert_true(dist <= 1.0)
}

///|
test "HybridStrategy::similarity is 1 - distance" {
  let strategy = HybridStrategy::new()
  let dist = strategy.distance("test one", "test two")
  let sim = strategy.similarity("test one", "test two")
  let sum = dist + sim
  assert_true(sum > 0.99 && sum < 1.01)
}

///|
test "calculate_adjacent_hybrid returns correct length" {
  let texts = ["a b", "b c", "c d", "d e"]
  let config = @types.HybridConfig::new()
  let result = calculate_adjacent_hybrid(texts, config)
  assert_eq(result.length(), 3)
}

///|
test "calculate_adjacent_hybrid with empty array" {
  let texts : Array[String] = []
  let config = @types.HybridConfig::new()
  let result = calculate_adjacent_hybrid(texts, config)
  assert_eq(result.length(), 0)
}

///|
test "calculate_adjacent_hybrid with single element" {
  let texts = ["only one"]
  let config = @types.HybridConfig::new()
  let result = calculate_adjacent_hybrid(texts, config)
  assert_eq(result.length(), 0)
}
