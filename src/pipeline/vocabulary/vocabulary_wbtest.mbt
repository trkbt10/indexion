// Tests for `measure_divergence`. Tokens are constructed directly as
// KGF-style feature strings (`Kind:value`, `vocab:word`) so the tests are
// independent of the upstream KGF tokenizer.

///|
test "include_vocab_terms=false (default) drops vocab:* gap candidates" {
  let source = ["Ident:alpha", "Ident:beta", "vocab:hello", "vocab:world"]
  let target = ["Ident:beta"]
  let config : GapConfig = {
    min_value_length: 2,
    max_terms: 0,
    include_vocab_terms: false,
  }
  let result = measure_divergence([source], [target], config)
  // Ident:alpha must surface; vocab:* must be filtered out.
  let values = result.gap_terms.map(fn(g) { g.value })
  assert_true(values.contains("alpha"))
  assert_false(values.contains("hello"))
  assert_false(values.contains("world"))
}

///|
test "include_vocab_terms=true surfaces vocab:* as gap candidates" {
  let source = ["Ident:alpha", "Ident:beta", "vocab:hello", "vocab:world"]
  let target = ["Ident:beta"]
  let config : GapConfig = {
    min_value_length: 2,
    max_terms: 0,
    include_vocab_terms: true,
  }
  let result = measure_divergence([source], [target], config)
  let values = result.gap_terms.map(fn(g) { g.value })
  // Both identifier-style and vocab:* drift terms must surface.
  assert_true(values.contains("alpha"))
  assert_true(values.contains("hello"))
  assert_true(values.contains("world"))
  // Ident:beta is in target, so it must NOT appear as drift.
  assert_false(values.contains("beta"))
}

///|
test "ubiquity clamp keeps gap terms on a 2-doc corpus" {
  // For total_docs = 2, the raw `n/3 + 1` formula yields a threshold of 1
  // which would discard every term (df ≥ 1 by definition). The clamp pins
  // the threshold at ≥ 2 so source-only terms survive.
  let source = ["Ident:alpha", "Ident:beta", "Ident:gamma"]
  let target = ["Ident:delta"]
  let config : GapConfig = {
    min_value_length: 2,
    max_terms: 0,
    include_vocab_terms: false,
  }
  let result = measure_divergence([source], [target], config)
  let values = result.gap_terms.map(fn(g) { g.value })
  assert_true(values.contains("alpha"))
  assert_true(values.contains("beta"))
  assert_true(values.contains("gamma"))
}

///|
test "larger corpus still filters ubiquitous terms" {
  // 6-doc corpus: `n/3 + 1 = 3`, above the clamp's minimum.
  // `Ident:common` appears in every doc → df=6 ≥ 3 → filtered out.
  // `Ident:rare` only in source[0] → df=1 → kept.
  let source : Array[Array[String]] = [
    ["Ident:common", "Ident:rare"],
    ["Ident:common"],
    ["Ident:common"],
  ]
  let target : Array[Array[String]] = [
    ["Ident:common"],
    ["Ident:common"],
    ["Ident:common"],
  ]
  let config : GapConfig = {
    min_value_length: 2,
    max_terms: 0,
    include_vocab_terms: false,
  }
  let result = measure_divergence(source, target, config)
  let values = result.gap_terms.map(fn(g) { g.value })
  assert_true(values.contains("rare"))
  assert_false(values.contains("common"))
}

///|
test "identical token bags yield zero cosine distance and empty gaps" {
  let bag = ["Ident:alpha", "Ident:beta", "vocab:hello"]
  let config : GapConfig = {
    min_value_length: 2,
    max_terms: 0,
    include_vocab_terms: true,
  }
  let result = measure_divergence([bag], [bag], config)
  assert_true(result.cosine_distance < 0.0001)
  assert_eq(result.gap_terms.length(), 0)
}

///|
test "disjoint token bags yield large cosine distance" {
  // Two non-overlapping vocabularies should produce cosine distance ≈ 1.0.
  let source = ["Ident:alpha", "Ident:beta", "Ident:gamma"]
  let target = ["Ident:delta", "Ident:epsilon", "Ident:zeta"]
  let config : GapConfig = {
    min_value_length: 2,
    max_terms: 0,
    include_vocab_terms: false,
  }
  let result = measure_divergence([source], [target], config)
  assert_true(result.cosine_distance > 0.9)
}

///|
test "max_terms caps the gap output" {
  let source = [
    "Ident:alpha",
    "Ident:beta",
    "Ident:gamma",
    "Ident:delta",
    "Ident:epsilon",
  ]
  let target = ["Ident:other"]
  let config : GapConfig = {
    min_value_length: 2,
    max_terms: 2,
    include_vocab_terms: false,
  }
  let result = measure_divergence([source], [target], config)
  assert_eq(result.gap_terms.length(), 2)
}

///|
test "min_value_length filters short identifier values" {
  // Values shorter than min_value_length are dropped before gap-term scoring.
  let source = ["Ident:a", "Ident:ab", "Ident:longer"]
  let target = ["Ident:other"]
  let config : GapConfig = {
    min_value_length: 3,
    max_terms: 0,
    include_vocab_terms: false,
  }
  let result = measure_divergence([source], [target], config)
  let values = result.gap_terms.map(fn(g) { g.value })
  assert_false(values.contains("a"))
  assert_false(values.contains("ab"))
  assert_true(values.contains("longer"))
}
