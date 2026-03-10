///|
/// Whitebox tests for similarity types and strategy dispatch.

///|
test "SimilarityResult::from_distance creates correct result" {
  let result = @types.SimilarityResult::from_distance(0.3)
  assert_true(result.get_distance() > 0.29 && result.get_distance() < 0.31)
  assert_true(result.get_similarity() > 0.69 && result.get_similarity() < 0.71)
}

///|
test "SimilarityResult::from_similarity creates correct result" {
  let result = @types.SimilarityResult::from_similarity(0.8)
  assert_true(result.get_similarity() > 0.79 && result.get_similarity() < 0.81)
  assert_true(result.get_distance() > 0.19 && result.get_distance() < 0.21)
}

///|
test "HybridConfig::new creates default config" {
  let config = @types.HybridConfig::new()
  assert_true(config.get_ncd_weight() > 0.49 && config.get_ncd_weight() < 0.51)
  assert_true(
    config.get_tfidf_weight() > 0.49 && config.get_tfidf_weight() < 0.51,
  )
}

///|
test "HybridConfig::create normalizes weights" {
  let config = @types.HybridConfig::create(3.0, 1.0)
  assert_true(config.get_ncd_weight() > 0.74 && config.get_ncd_weight() < 0.76)
  assert_true(
    config.get_tfidf_weight() > 0.24 && config.get_tfidf_weight() < 0.26,
  )
}

///|
test "HybridConfig::create handles zero weights" {
  let config = @types.HybridConfig::create(0.0, 0.0)
  // Should fall back to defaults
  assert_true(config.get_ncd_weight() > 0.49 && config.get_ncd_weight() < 0.51)
}

///|
test "HybridConfig::create handles negative weights" {
  let config = @types.HybridConfig::create(-1.0, 2.0)
  // Negative weight should be treated as 0
  assert_true(
    config.get_tfidf_weight() > 0.99 && config.get_tfidf_weight() < 1.01,
  )
}

///|
test "StrategyKind::parse parses valid names" {
  assert_true(StrategyKind::parse("ncd").is_empty() == false)
  assert_true(StrategyKind::parse("tfidf").is_empty() == false)
  assert_true(StrategyKind::parse("hybrid").is_empty() == false)
  assert_true(StrategyKind::parse("apted").is_empty() == false)
  assert_true(StrategyKind::parse("tsed").is_empty() == false)
}

///|
test "StrategyKind::parse returns None for invalid names" {
  assert_true(StrategyKind::parse("invalid").is_empty())
  assert_true(StrategyKind::parse("").is_empty())
}

///|
test "StrategyKind::name returns correct names" {
  assert_eq(StrategyKind::NCD.name(), "ncd")
  assert_eq(StrategyKind::TfIdf.name(), "tfidf")
  assert_eq(StrategyKind::Hybrid(@types.HybridConfig::new()).name(), "hybrid")
  assert_eq(StrategyKind::Apted.name(), "apted")
  assert_eq(StrategyKind::Tsed.name(), "tsed")
}

///|
test "StrategyKind::is_text_strategy" {
  assert_true(StrategyKind::NCD.is_text_strategy())
  assert_true(StrategyKind::TfIdf.is_text_strategy())
  assert_true(
    StrategyKind::Hybrid(@types.HybridConfig::new()).is_text_strategy(),
  )
  assert_true(StrategyKind::Apted.is_text_strategy() == false)
  assert_true(StrategyKind::Tsed.is_text_strategy() == false)
}

///|
test "StrategyKind::is_tree_strategy" {
  assert_true(StrategyKind::Apted.is_tree_strategy())
  assert_true(StrategyKind::Tsed.is_tree_strategy())
  assert_true(StrategyKind::NCD.is_tree_strategy() == false)
}
