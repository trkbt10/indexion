///|
test "build_bm25_vector returns empty for empty tokens" {
  let df : Map[String, Int] = Map([])
  let vec = build_bm25_vector([], df, 10, 100.0)
  assert_true(vec.is_empty())
}

///|
test "build_bm25_vector produces non-zero weights" {
  let tokens = ["hello", "world", "hello"]
  let df : Map[String, Int] = { "hello": 2, "world": 1 }
  let vec = build_bm25_vector(tokens, df, 10, 3.0)
  assert_true(vec.get("hello") > 0.0)
  assert_true(vec.get("world") > 0.0)
}

///|
test "BM25 saturates repeated terms" {
  // With BM25, doubling term count should NOT double the weight
  let df : Map[String, Int] = { "x": 1 }
  let tokens_low = ["x", "x"]
  let tokens_high = ["x", "x", "x", "x", "x", "x", "x", "x", "x", "x"]
  let vec_low = build_bm25_vector(tokens_low, df, 10, 5.0)
  let vec_high = build_bm25_vector(tokens_high, df, 10, 5.0)
  let w_low = vec_low.get("x")
  let w_high = vec_high.get("x")
  // Weight should increase but not linearly
  assert_true(w_high > w_low)
  // 5x more occurrences should give less than 5x weight increase
  assert_true(w_high < w_low * 5.0)
}

///|
test "BM25 normalizes by document length" {
  // Same term count but different document lengths should produce different weights
  let df : Map[String, Int] = { "x": 1, "y": 1 }
  // Short doc: 2 tokens
  let tokens_short = ["x", "y"]
  // Long doc: same terms padded with filler (10 tokens)
  let tokens_long = ["x", "y", "a", "b", "c", "d", "e", "f", "g", "h"]
  let df_long : Map[String, Int] = {
    "x": 1,
    "y": 1,
    "a": 1,
    "b": 1,
    "c": 1,
    "d": 1,
    "e": 1,
    "f": 1,
    "g": 1,
    "h": 1,
  }
  let avg_dl = 6.0 // average across corpus
  let vec_short = build_bm25_vector(tokens_short, df, 10, avg_dl)
  let vec_long = build_bm25_vector(tokens_long, df_long, 10, avg_dl)
  // "x" should have higher weight in short doc (less diluted)
  assert_true(vec_short.get("x") > vec_long.get("x"))
}

///|
test "BM25Batch::from_tokens creates batch with correct size" {
  let tokenized = [["a", "b", "c"], ["b", "c", "d"], ["d", "e", "f"]]
  let batch = BM25Batch::from_tokens(tokenized)
  assert_eq(batch.length(), 3)
}

///|
test "BM25Batch::similarity returns 1.0 for same document" {
  let tokenized = [["a", "b", "c"], ["d", "e", "f"]]
  let batch = BM25Batch::from_tokens(tokenized)
  assert_eq(batch.similarity(0, 0), 1.0)
}

///|
test "BM25Batch::similarity is higher for similar documents" {
  let tokenized = [
    ["fn", "main", "let", "x", "return"],
    ["fn", "main", "let", "y", "return"],
    ["import", "os", "sys", "path", "join"],
  ]
  let batch = BM25Batch::from_tokens(tokenized)
  let sim_01 = batch.similarity(0, 1)
  let sim_02 = batch.similarity(0, 2)
  assert_true(sim_01 > sim_02)
}

///|
test "BM25Batch::all_pairs_above_threshold filters correctly" {
  let tokenized = [
    ["a", "b", "c", "d"],
    ["a", "b", "c", "e"],
    ["x", "y", "z", "w"],
  ]
  let batch = BM25Batch::from_tokens(tokenized)
  let results = batch.all_pairs_above_threshold(0.3)
  // (0,1) should be similar, (0,2) and (1,2) should not
  let mut found_01 = false
  for result in results {
    let (i, j, sim) = result
    assert_true(sim >= 0.3)
    let lo = if i < j { i } else { j }
    let hi = if i < j { j } else { i }
    if lo == 0 && hi == 1 {
      found_01 = true
    }
  }
  assert_true(found_01)
}
