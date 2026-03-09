///|
fn has_pair(pairs : Array[(Int, Int, Double)], left : Int, right : Int) -> Bool {
  for pair in pairs {
    let (i, j, _) = pair
    if i == left && j == right {
      return true
    }
  }
  false
}

///|
test "TfidfBatch all_pairs_above_threshold keeps only overlapping candidates" {
  let batch = TfidfBatch::from_tokens([
    ["alpha", "one"], ["alpha", "two"], ["zzzz", "yyyy"], ["one", "two"],
  ])
  let pairs = batch.all_pairs_above_threshold(0.01)
  assert_true(has_pair(pairs, 0, 1))
  assert_true(has_pair(pairs, 0, 3))
  assert_true(has_pair(pairs, 1, 3))
  assert_false(has_pair(pairs, 0, 2))
  assert_false(has_pair(pairs, 1, 2))
  assert_false(has_pair(pairs, 2, 3))
}

///|
test "TfidfBatch all_pairs_above_threshold with zero threshold returns all pairs" {
  let batch = TfidfBatch::from_tokens([
    ["alpha", "beta"], ["alpha", "gamma"], ["delta"],
  ])
  let pairs = batch.all_pairs_above_threshold(0.0)
  assert_eq(pairs.length(), 3)
  assert_true(has_pair(pairs, 0, 1))
  assert_true(has_pair(pairs, 0, 2))
  assert_true(has_pair(pairs, 1, 2))
}

///|
test "TfidfBatch from_tokens builds correct stats" {
  let batch = TfidfBatch::from_tokens([
    ["import", "react"], ["export", "const", "value"],
  ])
  let stats = batch.build_stats()
  assert_eq(stats.document_count, 2)
  assert_eq(stats.total_tokens, 5)
}

///|
test "TfidfBatch from_tokens with cjk tokens" {
  let batch = TfidfBatch::from_tokens([
    ["const", "label", "日本"], ["const", "label", "日本", "国語"],
  ])
  let pairs = batch.all_pairs_above_threshold(0.01)
  assert_eq(pairs.length(), 1)
  let (_, _, similarity) = pairs[0]
  assert_true(similarity > 0.0)
}

///|
test "TfidfBatch all_pairs_above_threshold_with_stats reports counts" {
  let batch = TfidfBatch::from_tokens([
    ["alpha", "beta", "gamma"], ["alpha", "beta"], ["delta", "epsilon"],
  ])
  let (pairs, stats) = batch.all_pairs_above_threshold_with_stats(0.1)
  assert_eq(stats.output_pairs, pairs.length())
  assert_true(stats.candidate_pairs >= pairs.length())
  assert_true(stats.cosine_evaluations >= pairs.length())
  assert_true(has_pair(pairs, 0, 1))
}
