// Positive-detection tests for n:m story divergence.
//
// These tests construct minimal in-memory `StoryGroups` values where the
// expected divergences are known by construction. They guard against
// silent regressions in the divergence pipeline: if the engine stops
// detecting a term we deliberately seeded, the test fails with a
// specific seed name.
//
// Each test follows the same pattern:
//   1. Build N spec documents and M impl documents in code (no disk I/O).
//   2. Plant a known seed term that appears in exactly one side.
//   3. Run analyze_story.
//   4. Assert the seed term appears in the corresponding gap list.
//
// Real fixtures (fixtures/story/...) prove the pipeline runs on real
// text but cannot prove a particular detection holds, because their
// ground truth is informal (a README ledger). These tests provide the
// formal ground truth.

///|
/// Build a StoryDocument inline.
fn make_doc(path : String, content : String) -> StoryDocument {
  StoryDocument::new(path, content)
}

///|
/// Check that a value appears in the under-coverage list.
fn under_contains(report : StoryReport, value : String) -> Bool {
  for u in report.under_coverage {
    if u.value == value {
      return true
    }
  }
  false
}

///|
/// Check that a value appears in the out-of-source list.
fn out_contains(report : StoryReport, value : String) -> Bool {
  for o in report.out_of_source {
    if o.value == value {
      return true
    }
  }
  false
}

///|
test "out-of-source: impl-only proper noun is detected (English)" {
  // The spec side mentions only the protagonist Aldous and his sister.
  // The impl side introduces a butler "Parkinson" — a name with no spec
  // provenance. This is the canonical drift case: a character introduced
  // at the impl layer that the writer never declared in the cast list.
  let spec = [
    make_doc(
      "spec/plot.md",
      "Act 1: Aldous returns to the manor. Act 2: Aldous quarrels with his sister Margaret. Act 3: Aldous departs.",
    ),
    make_doc(
      "spec/characters.md",
      "Aldous is the protagonist. Margaret is his sister. They have known each other for thirty years.",
    ),
    make_doc(
      "spec/settings.md",
      "The manor sits on a windswept moor. The hall has wooden panelling and a vaulted ceiling.",
    ),
  ]
  let impl_ = [
    make_doc(
      "impl/01.md",
      "Aldous walked into the hall. Parkinson the butler bowed. Margaret was already waiting by the fireplace.",
    ),
    make_doc(
      "impl/02.md",
      "Parkinson served the tea while Aldous and Margaret argued about the inheritance.",
    ),
  ]
  let groups = StoryGroups::new(spec, impl_)
  let config = StoryConfig::new(max_terms=50, min_value_length=2)
  let report = analyze_story(groups, config)
  assert_true(out_contains(report, "parkinson"))
}

///|
test "under-coverage: spec-only motif is detected (English)" {
  // The spec side promises a "lighthouse" as a recurring motif and a
  // "telegram" arriving in act 2. The impl side never mentions either.
  let spec = [
    make_doc(
      "spec/plot.md",
      "Act 1: introduction at the lighthouse. Act 2: a fateful telegram arrives. Act 3: confrontation.",
    ),
    make_doc(
      "spec/revisions.md",
      "The lighthouse remains the central image; the telegram should be visible on the desk in every scene.",
    ),
    make_doc(
      "spec/characters.md",
      "Captain Halloway runs the lighthouse. His daughter is named Ophelia.",
    ),
  ]
  let impl_ = [
    make_doc(
      "impl/01.md",
      "Captain Halloway poured the brandy and watched the rain through the window. Ophelia stood by the door, silent.",
    ),
    make_doc(
      "impl/02.md",
      "Halloway crossed the room. Ophelia would not meet his eye. The clock struck nine.",
    ),
  ]
  let groups = StoryGroups::new(spec, impl_)
  let config = StoryConfig::new(max_terms=50, min_value_length=2)
  let report = analyze_story(groups, config)
  assert_true(under_contains(report, "lighthouse"))
  assert_true(under_contains(report, "telegram"))
}

///|
test "out-of-source: impl-only object is detected (Japanese CJK)" {
  // 日本語コーパスで本文側にだけ登場する名詞「銀懐中」を仕込む。
  // 仕様側は plot 二稿と人物表で、いずれにも現れない。CJK 経路
  // (Kanji ラン)が機能していることの確認も兼ねる。
  let spec = [
    make_doc(
      "spec/plot1.md",
      "第一幕：青年が東京の下宿屋に到着する。第二幕：師匠と再会する。第三幕：別れを告げる。",
    ),
    make_doc(
      "spec/plot2.md",
      "改稿。第一幕で青年は柳行李を抱えている。第二幕で師匠は煎茶を勧める。",
    ),
    make_doc(
      "spec/characters.md",
      "青年は二十二歳の書生。師匠は五十がらみの漢学者で、白い顎髭を蓄えている。",
    ),
  ]
  let impl_ = [
    make_doc(
      "impl/01.md",
      "青年は下宿屋の門前に立ち、懐から銀懐中を取り出して時刻を確かめた。下宿屋の女将が出迎えた。",
    ),
    make_doc(
      "impl/02.md",
      "師匠の書斎に通された青年は、銀懐中を懐に戻し、煎茶の湯気を見つめていた。",
    ),
  ]
  let groups = StoryGroups::new(spec, impl_)
  let config = StoryConfig::new(max_terms=50, min_value_length=2)
  let report = analyze_story(groups, config)
  // KGF Japanese 漢字トークンは連続漢字を1トークンに切り出すため、
  // 「銀懐中」が丸ごと出るのが通常。短い構成要素「銀懐」「懐中」が
  // 現れる可能性もあるが、いずれかが out_of_source に残ればよい。
  let detected = out_contains(report, "銀懐中") ||
    out_contains(report, "銀懐") ||
    out_contains(report, "懐中")
  assert_true(detected)
}

///|
test "under-coverage: spec-only Japanese motif is detected (CJK)" {
  // 仕様側が「白椿」を象徴として指定するが、本文には登場しない欠落ケース。
  let spec = [
    make_doc(
      "spec/plot.md",
      "第一幕：庭園の白椿が散り始める。第二幕：白椿の下で約束が交わされる。",
    ),
    make_doc(
      "spec/settings.md",
      "庭園には白椿の木が数本ある。白椿は物語全体を貫く象徴である。",
    ),
    make_doc(
      "spec/characters.md",
      "令嬢は十八歳。礼儀作法に厳しく育てられた。",
    ),
  ]
  let impl_ = [
    make_doc(
      "impl/01.md",
      "令嬢は庭園を歩いた。風が冷たかった。彼女は何も言わず立ち止まった。",
    ),
    make_doc(
      "impl/02.md",
      "令嬢は再び庭園に出た。空はどんよりと曇っていた。",
    ),
  ]
  let groups = StoryGroups::new(spec, impl_)
  let config = StoryConfig::new(max_terms=50, min_value_length=2)
  let report = analyze_story(groups, config)
  let detected = under_contains(report, "白椿") || under_contains(report, "椿")
  assert_true(detected)
}

///|
test "negative control: terms shared by both sides do not appear as gaps" {
  // 全文書に共通して登場する語が gap list に紛れ込まないことを確認する。
  let spec = [
    make_doc(
      "spec/plot.md",
      "Halloway visits the harbour. Halloway speaks with the harbour-master. Halloway leaves the harbour.",
    ),
    make_doc(
      "spec/characters.md",
      "Halloway is a captain. The harbour is his domain.",
    ),
  ]
  let impl_ = [
    make_doc(
      "impl/01.md",
      "Halloway walked along the harbour. The wind pulled at his coat. The harbour was silent.",
    ),
    make_doc(
      "impl/02.md",
      "Halloway looked back at the harbour. He had not slept.",
    ),
  ]
  let groups = StoryGroups::new(spec, impl_)
  let config = StoryConfig::new(max_terms=50, min_value_length=2)
  let report = analyze_story(groups, config)
  assert_false(under_contains(report, "halloway"))
  assert_false(under_contains(report, "harbour"))
  assert_false(out_contains(report, "halloway"))
  assert_false(out_contains(report, "harbour"))
}
