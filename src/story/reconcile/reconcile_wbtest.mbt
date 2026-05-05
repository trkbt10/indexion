/// Positive-detection tests for reconcile's `covered_terms` field.
///
/// `covered_terms` is the BM25-weighted intersection of the act
/// vocabulary and the best-matching impl vocabulary. It exists because
/// `missing_terms` (act tokens NOT in impl) and `extra_terms` (impl
/// tokens NOT in act) deliberately exclude the intersection, leaving
/// callers with no way to surface "what survived in both" — which is
/// the leak signal when reconcile is run in inverted polarity (spec
/// corpus = constraints the impl must NOT echo).
///
/// These tests construct minimal in-memory groups where the
/// intersection is known by construction, then assert that
/// `covered_terms` carries it back.

///|
fn make_doc(path : String, content : String) -> @story.StoryDocument {
  @story.StoryDocument::new(path, content)
}

///|
fn covered_contains(c : ActReconcileCandidate, value : String) -> Bool {
  for t in c.get_covered_terms() {
    if t == value {
      return true
    }
  }
  false
}

///|
fn missing_contains(c : ActReconcileCandidate, value : String) -> Bool {
  for t in c.get_missing_terms() {
    if t == value {
      return true
    }
  }
  false
}

///|
test "covered_terms surfaces tokens present in both act and impl" {
  // Spec carries one act with three planted content tokens (Aldous,
  // Margaret, Parkinson). Impl is a prose draft that mentions Aldous
  // and Margaret but not Parkinson.
  let spec = [
    make_doc(
      "spec/act.md",
      "Aldous returns to the manor and quarrels with his sister Margaret about Parkinson.",
    ),
  ]
  let impl_docs = [
    make_doc(
      "impl/scene.md",
      "Aldous walks through the door of the manor. His sister Margaret looks up from the desk.",
    ),
  ]
  let groups = @story.StoryGroups::new(spec, impl_docs)
  let report = reconcile(groups, ReconcileConfig::new(similarity_floor=0.0))
  let candidates = report.get_candidates()
  assert_eq(candidates.length(), 1)
  let c = candidates[0]
  // Aldous and Margaret are in both → covered.
  // Parkinson is in spec but not impl → missing.
  // (In Japanese-style proper-noun extraction these would be different
  //  tokens; for English-only fixture the KGF EnProperNoun kind picks
  //  them up cleanly.)
  assert_true(covered_contains(c, "aldous"))
  assert_true(covered_contains(c, "margaret"))
  assert_true(missing_contains(c, "parkinson"))
}

///|
test "covered_terms is empty when impl has no overlap with act" {
  let spec = [
    make_doc(
      "spec/act.md",
      "Aldous returns to the manor.",
    ),
  ]
  let impl_docs = [
    make_doc(
      "impl/scene.md",
      "Beatrice descends the staircase.",
    ),
  ]
  let groups = @story.StoryGroups::new(spec, impl_docs)
  let report = reconcile(groups, ReconcileConfig::new(similarity_floor=0.0))
  let candidates = report.get_candidates()
  assert_eq(candidates.length(), 1)
  let c = candidates[0]
  // No proper noun overlaps. covered_terms must be empty (or contain
  // only function-word-level tokens that the KGF filter dropped).
  for t in c.get_covered_terms() {
    assert_true(t != "aldous")
    assert_true(t != "manor")
    assert_true(t != "beatrice")
    assert_true(t != "staircase")
  }
}

///|
test "inverted-polarity usage: lint corpus as spec, leak terms surface as covered" {
  // The intended dual usage: spec is constraint vocabulary the impl
  // must NOT echo. A "covered" term is then a leak.
  let lint_spec = [
    make_doc(
      "lint/no-explain.md",
      "Do not write the word stoic. Do not call the voice mechanical.",
    ),
  ]
  let prose = [
    make_doc(
      "prose/chapter.md",
      "He looked stoic. The voice came through, mechanical and even.",
    ),
  ]
  let groups = @story.StoryGroups::new(lint_spec, prose)
  let report = reconcile(groups, ReconcileConfig::new(similarity_floor=0.0))
  let candidates = report.get_candidates()
  assert_eq(candidates.length(), 1)
  let c = candidates[0]
  // The prose echoed both forbidden words. covered_terms must surface
  // them — that is the leak signal the project pipeline reads.
  assert_true(covered_contains(c, "stoic"))
  assert_true(covered_contains(c, "mechanical"))
}
