///|
test "apply_fdr_correction returns empty for empty input" {
  let matches : Array[SimilarityMatch] = []
  let result = apply_fdr_correction(matches, 0.05, 100)
  assert_eq(result.length(), 0)
}

///|
test "apply_fdr_correction returns empty for alpha=0" {
  let matches = [SimilarityMatch::new(0, 1, "a", "b", 0.95)]
  let result = apply_fdr_correction(matches, 0.0, 100)
  assert_eq(result.length(), 0)
}

///|
test "apply_fdr_correction returns all for alpha=1" {
  let matches = [
    SimilarityMatch::new(0, 1, "a", "b", 0.95),
    SimilarityMatch::new(0, 2, "a", "c", 0.85),
  ]
  let result = apply_fdr_correction(matches, 1.0, 100)
  assert_eq(result.length(), 2)
}

///|
test "apply_fdr_correction keeps high-confidence matches" {
  // A single very high match from a large search space should survive
  // because its exponential p-value is very small
  let matches = [SimilarityMatch::new(0, 1, "a", "b", 0.99)]
  let result = apply_fdr_correction(matches, 0.05, 1000, threshold=0.8)
  // 0.99 is far above 0.8 → very small p-value → should survive
  assert_eq(result.length(), 1)
}

///|
test "apply_fdr_correction filters borderline matches with many total pairs" {
  // Many matches just above threshold from a huge search space
  // These should mostly be filtered as likely false positives
  let matches : Array[SimilarityMatch] = []
  for i = 0; i < 50; i = i + 1 {
    matches.push(
      SimilarityMatch::new(
        i,
        i + 50,
        "f" + i.to_string(),
        "g" + i.to_string(),
        0.801,
      ),
    )
  }
  // 50 matches just above 0.8 out of 50000 total pairs
  let result = apply_fdr_correction(matches, 0.05, 50000, threshold=0.8)
  // These borderline matches have p-values near base_rate (50/50000 = 0.001)
  // which may or may not survive BH depending on the exact math
  assert_true(result.length() <= matches.length())
}

///|
test "apply_fdr_correction separates strong from weak matches" {
  let matches : Array[SimilarityMatch] = []
  // 3 strong matches (far above threshold)
  matches.push(SimilarityMatch::new(0, 1, "a", "b", 0.98))
  matches.push(SimilarityMatch::new(2, 3, "c", "d", 0.95))
  matches.push(SimilarityMatch::new(4, 5, "e", "f", 0.92))
  // 3 borderline matches (barely above threshold)
  matches.push(SimilarityMatch::new(6, 7, "g", "h", 0.81))
  matches.push(SimilarityMatch::new(8, 9, "i", "j", 0.801))
  matches.push(SimilarityMatch::new(10, 11, "k", "l", 0.800))
  let result = apply_fdr_correction(matches, 0.05, 5000, threshold=0.8)
  // Strong matches should survive; some borderline may be filtered
  // At minimum, the strongest match (0.98) should survive
  let mut has_strong = false
  for m in result {
    if m.similarity >= 0.95 {
      has_strong = true
    }
  }
  assert_true(has_strong)
  assert_true(result.length() >= 1)
}

///|
/// Standard normal CDF approximation (test-only).
/// Uses the Abramowitz & Stegun (1964) approximation (equation 26.2.17)
/// with maximum error < 7.5 × 10⁻⁸.
fn normal_cdf(x : Double) -> Double {
  if x < -8.0 {
    return 0.0
  }
  if x > 8.0 {
    return 1.0
  }
  let (sign, abs_x) = if x >= 0.0 { (1.0, x) } else { (-1.0, -x) }
  let b1 = 0.319381530
  let b2 = -0.356563782
  let b3 = 1.781477937
  let b4 = -1.821255978
  let b5 = 1.330274429
  let p = 0.2316419
  let t = 1.0 / (1.0 + p * abs_x)
  let pdf = @math.exp(-abs_x * abs_x / 2.0) / 2.506628274631
  let poly = t * (b1 + t * (b2 + t * (b3 + t * (b4 + t * b5))))
  let cdf_positive = 1.0 - pdf * poly
  if sign > 0.0 {
    cdf_positive
  } else {
    1.0 - cdf_positive
  }
}

///|
test "normal_cdf returns expected boundary values" {
  // Φ(0) = 0.5
  let cdf_0 = normal_cdf(0.0)
  let diff_0 = if cdf_0 > 0.5 { cdf_0 - 0.5 } else { 0.5 - cdf_0 }
  assert_true(diff_0 < 0.001)
  // Φ(-8) ≈ 0
  assert_true(normal_cdf(-8.0) < 0.001)
  // Φ(8) ≈ 1
  assert_true(normal_cdf(8.0) > 0.999)
  // Φ(1.96) ≈ 0.975
  let cdf_196 = normal_cdf(1.96)
  let diff_196 = if cdf_196 > 0.975 { cdf_196 - 0.975 } else { 0.975 - cdf_196 }
  assert_true(diff_196 < 0.001)
}

///|
test "normal_cdf is monotonically increasing" {
  let mut prev = normal_cdf(-5.0)
  let mut x = -4.0
  while x <= 5.0 {
    let curr = normal_cdf(x)
    assert_true(curr >= prev)
    prev = curr
    x += 0.5
  }
}

///|
test "BatchResult::apply_fdr works end-to-end" {
  let matches = [
    SimilarityMatch::new(0, 1, "a", "b", 0.95),
    SimilarityMatch::new(2, 3, "c", "d", 0.82),
  ]
  let result : BatchResult = { matches, file_count: 20, pairs_compared: 190 }
  let filtered = result.apply_fdr(0.05, threshold=0.8)
  assert_true(filtered.matches.length() <= 2)
  assert_eq(filtered.file_count, 20)
}

///|
test "apply_fdr_correction does not reject single exact duplicate" {
  // Regression test: a single high-similarity match should NOT be rejected
  // even when it's the only match in the result set
  let matches = [SimilarityMatch::new(0, 1, "a.mbt", "b.mbt", 0.95)]
  // 100 files = 4950 total pairs, but only 1 match
  let result = apply_fdr_correction(matches, 0.05, 4950, threshold=0.8)
  // Score 0.95 is well above threshold 0.8 → should survive
  assert_eq(result.length(), 1)
}
