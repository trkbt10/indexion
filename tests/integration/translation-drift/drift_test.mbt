// Integration tests for `plan drift` against fixtures/translation-drift/.
//
// Each test drives `@drift.build_report` directly (the same entry point the
// CLI uses after argparse) and asserts the observable signal for one drift
// scenario.

///|
using @test {assert_eq}

///|
fn fixture(rel : String) -> String {
  "fixtures/translation-drift/" + rel
}

///|
fn run_pair(a : String, b : String) -> @drift.DriftReport raise {
  let config : @drift.DriftConfig = {
    ..@drift.DriftConfig::default(),
    file_a: a,
    file_b: b,
    top: 0,
  }
  match @drift.build_report(config) {
    Some(r) => r
    None => fail("build_report returned None for " + a + " vs " + b)
  }
}

///|
fn values(direction : @drift.DriftDirection) -> Array[String] {
  direction.gap_terms.map(fn(t) { t.value })
}

///|
test "identical: cosine ~= 0 and both gap directions empty" {
  let report = run_pair(
    fixture("identical/README-a.md"),
    fixture("identical/README-b.md"),
  )
  assert_true(report.cosine_distance < 0.0001)
  assert_eq(report.a_to_b.gap_terms.length(), 0)
  assert_eq(report.b_to_a.gap_terms.length(), 0)
}

///|
test "drifted: EN-side surfaces locale/overrides added on the EN side" {
  let report = run_pair(
    fixture("drifted/README-en.md"),
    fixture("drifted/README-ja.md"),
  )
  let en_only = values(report.a_to_b)
  assert_true(en_only.contains("locale"))
  assert_true(en_only.contains("overrides"))
}

///|
test "reverse-drift: JA-side surfaces locale/refresh added on the JA side" {
  let report = run_pair(
    fixture("reverse-drift/README-en.md"),
    fixture("reverse-drift/README-ja.md"),
  )
  let ja_only = values(report.b_to_a)
  assert_true(ja_only.contains("locale"))
  assert_true(ja_only.contains("refresh"))
  // ...and EN-side does not falsely claim those terms are missing
  let en_only = values(report.a_to_b)
  assert_false(en_only.contains("locale"))
  assert_false(en_only.contains("refresh"))
}

///|
test "same-language: drift terms only on the updated side, no prose noise" {
  let report = run_pair(
    fixture("same-language/README-old.md"),
    fixture("same-language/README-new.md"),
  )
  // Old side has no new vocab → empty
  assert_eq(report.a_to_b.gap_terms.length(), 0)
  // New side has the introduced terms
  let new_only = values(report.b_to_a)
  assert_true(new_only.contains("locale"))
  assert_true(new_only.contains("overrides"))
  // The shared identifier vocabulary keeps cos close to 1
  assert_true(report.cosine_distance < 0.2)
}

///|
test "synced: cosine distance order — synced < drifted < unrelated" {
  let synced = run_pair(
    fixture("synced/README-en.md"),
    fixture("synced/README-ja.md"),
  )
  let drifted = run_pair(
    fixture("drifted/README-en.md"),
    fixture("drifted/README-ja.md"),
  )
  let unrelated = run_pair(
    fixture("unrelated/README-en.md"),
    fixture("unrelated/README-ja.md"),
  )
  assert_true(synced.cosine_distance < drifted.cosine_distance)
  assert_true(drifted.cosine_distance < unrelated.cosine_distance)
}

///|
test "partial-translation: untranslated section surfaces on EN side" {
  let report = run_pair(
    fixture("partial-translation/README-en.md"),
    fixture("partial-translation/README-ja.md"),
  )
  let en_only = values(report.a_to_b)
  // The omitted API + License sections leave behind these prose tokens.
  assert_true(en_only.contains("license"))
  assert_true(en_only.contains("selector"))
}

///|
test "code-heavy: shared code blocks keep distance very small" {
  let report = run_pair(
    fixture("code-heavy/README-en.md"),
    fixture("code-heavy/README-ja.md"),
  )
  assert_true(report.cosine_distance < 0.1)
}

///|
test "threshold gate: reports passed=true when distance <= threshold" {
  let config : @drift.DriftConfig = {
    ..@drift.DriftConfig::default(),
    file_a: fixture("identical/README-a.md"),
    file_b: fixture("identical/README-b.md"),
    vocab_threshold: Some(0.1),
  }
  let report = match @drift.build_report(config) {
    Some(r) => r
    None => return fail("build_report returned None")
  }
  assert_eq(report.threshold, Some(0.1))
  assert_eq(report.threshold_passed, Some(true))
}

///|
test "threshold gate: reports passed=false when distance > threshold" {
  let config : @drift.DriftConfig = {
    ..@drift.DriftConfig::default(),
    file_a: fixture("unrelated/README-en.md"),
    file_b: fixture("unrelated/README-ja.md"),
    vocab_threshold: Some(0.1),
  }
  let report = match @drift.build_report(config) {
    Some(r) => r
    None => return fail("build_report returned None")
  }
  assert_eq(report.threshold_passed, Some(false))
}
