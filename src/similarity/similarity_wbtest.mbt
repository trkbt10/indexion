// Whitebox tests for similarity strategies.

///|
test "SimilarityResult::from_distance creates correct result" {
  let result = SimilarityResult::from_distance(0.3)
  assert_true(result.get_distance() > 0.29 && result.get_distance() < 0.31)
  assert_true(result.get_similarity() > 0.69 && result.get_similarity() < 0.71)
}

///|
test "SimilarityResult::from_similarity creates correct result" {
  let result = SimilarityResult::from_similarity(0.8)
  assert_true(result.get_similarity() > 0.79 && result.get_similarity() < 0.81)
  assert_true(result.get_distance() > 0.19 && result.get_distance() < 0.21)
}

///|
test "HybridConfig::new creates default config" {
  let config = HybridConfig::new()
  assert_true(config.get_ncd_weight() > 0.49 && config.get_ncd_weight() < 0.51)
  assert_true(
    config.get_tfidf_weight() > 0.49 && config.get_tfidf_weight() < 0.51,
  )
}

///|
test "HybridConfig::create normalizes weights" {
  let config = HybridConfig::create(3.0, 1.0)
  assert_true(config.get_ncd_weight() > 0.74 && config.get_ncd_weight() < 0.76)
  assert_true(
    config.get_tfidf_weight() > 0.24 && config.get_tfidf_weight() < 0.26,
  )
}

///|
test "HybridConfig::create handles zero weights" {
  let config = HybridConfig::create(0.0, 0.0)
  // Should fall back to defaults
  assert_true(config.get_ncd_weight() > 0.49 && config.get_ncd_weight() < 0.51)
}

///|
test "HybridConfig::create handles negative weights" {
  let config = HybridConfig::create(-1.0, 2.0)
  // Negative weight should be treated as 0
  assert_true(
    config.get_tfidf_weight() > 0.99 && config.get_tfidf_weight() < 1.01,
  )
}

// ============================================================
// NCDStrategy tests
// ============================================================

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

// ============================================================
// TfidfStrategy tests (NOTE: String-based distance is deprecated)
// ============================================================

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

// ============================================================
// HybridStrategy tests
// ============================================================

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
  let config = HybridConfig::new()
  let result = calculate_adjacent_hybrid(texts, config)
  assert_eq(result.length(), 3)
}

///|
test "calculate_adjacent_hybrid with empty array" {
  let texts : Array[String] = []
  let config = HybridConfig::new()
  let result = calculate_adjacent_hybrid(texts, config)
  assert_eq(result.length(), 0)
}

///|
test "calculate_adjacent_hybrid with single element" {
  let texts = ["only one"]
  let config = HybridConfig::new()
  let result = calculate_adjacent_hybrid(texts, config)
  assert_eq(result.length(), 0)
}
