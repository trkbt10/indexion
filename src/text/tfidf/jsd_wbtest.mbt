///|
test "jensen_shannon_divergence returns 0 for identical distributions" {
  let tf : Map[String, Int] = { "a": 5, "b": 3, "c": 2 }
  let jsd = jensen_shannon_divergence(tf, tf)
  assert_true(jsd < 0.001)
}

///|
test "jensen_shannon_divergence returns 1 for disjoint distributions" {
  let tf_a : Map[String, Int] = { "a": 5, "b": 3 }
  let tf_b : Map[String, Int] = { "c": 5, "d": 3 }
  let jsd = jensen_shannon_divergence(tf_a, tf_b)
  assert_true(jsd > 0.99)
}

///|
test "jensen_shannon_divergence is symmetric" {
  let tf_a : Map[String, Int] = { "a": 5, "b": 3, "c": 1 }
  let tf_b : Map[String, Int] = { "a": 2, "b": 6, "d": 4 }
  let jsd_ab = jensen_shannon_divergence(tf_a, tf_b)
  let jsd_ba = jensen_shannon_divergence(tf_b, tf_a)
  // Should be equal within floating point tolerance
  let diff = if jsd_ab > jsd_ba { jsd_ab - jsd_ba } else { jsd_ba - jsd_ab }
  assert_true(diff < 1.0e-10)
}

///|
test "jensen_shannon_divergence handles empty inputs" {
  let empty : Map[String, Int] = Map([])
  let non_empty : Map[String, Int] = { "a": 1 }
  assert_eq(jensen_shannon_divergence(empty, empty), 0.0)
  assert_eq(jensen_shannon_divergence(empty, non_empty), 1.0)
  assert_eq(jensen_shannon_divergence(non_empty, empty), 1.0)
}

///|
test "jensen_shannon_divergence is bounded in [0, 1]" {
  let tf_a : Map[String, Int] = { "a": 10, "b": 1 }
  let tf_b : Map[String, Int] = { "a": 1, "b": 10 }
  let jsd = jensen_shannon_divergence(tf_a, tf_b)
  assert_true(jsd >= 0.0)
  assert_true(jsd <= 1.0)
}

///|
test "jsd_from_tokens produces reasonable values" {
  let tokens_a = ["fn", "main", "let", "x", "return"]
  let tokens_b = ["fn", "main", "let", "y", "return"]
  let jsd = jsd_from_tokens(tokens_a, tokens_b)
  // High overlap → low divergence
  assert_true(jsd < 0.5)
}

///|
test "jsd_similarity is complement of jsd_from_tokens" {
  let tokens_a = ["a", "b", "c"]
  let tokens_b = ["a", "b", "d"]
  let jsd = jsd_from_tokens(tokens_a, tokens_b)
  let sim = jsd_similarity(tokens_a, tokens_b)
  let diff = if sim + jsd - 1.0 > 0.0 {
    sim + jsd - 1.0
  } else {
    1.0 - sim - jsd
  }
  assert_true(diff < 1.0e-10)
}

///|
test "JSDBatch::from_tokens creates batch" {
  let tokenized = [["a", "b"], ["b", "c"], ["d", "e"]]
  let batch = JSDBatch::from_tokens(tokenized)
  assert_eq(batch.length(), 3)
}

///|
test "JSDBatch::similarity returns 1.0 for same document" {
  let tokenized = [["a", "b", "c"]]
  let batch = JSDBatch::from_tokens(tokenized)
  assert_eq(batch.similarity(0, 0), 1.0)
}

///|
test "JSDBatch::all_pairs_above_threshold returns correct pairs" {
  let tokenized = [
    ["a", "b", "c", "d"],
    ["a", "b", "c", "e"],
    ["x", "y", "z", "w"],
  ]
  let batch = JSDBatch::from_tokens(tokenized)
  let results = batch.all_pairs_above_threshold(0.5)
  // (0,1) should be similar
  let mut found_01 = false
  for result in results {
    let (i, j, sim) = result
    assert_true(sim >= 0.5)
    if i == 0 && j == 1 {
      found_01 = true
    }
  }
  assert_true(found_01)
}
