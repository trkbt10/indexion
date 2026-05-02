// Positive-detection tests for n:m story divergence.
//
// These tests construct minimal in-memory StoryDataset values where the
// expected divergences are known by construction. They guard against silent
// regressions in the divergence pipeline: if the engine stops detecting a
// term we deliberately seeded, the test fails with a specific seed name.
//
// Each test follows the same pattern:
//   1. Build N source documents and M prose documents in code (no disk I/O).
//   2. Plant a known seed term that appears in exactly one side.
//   3. Run analyze_story.
//   4. Assert the seed term appears in the corresponding gap list.
//
// The fixtures used for end-to-end dogfooding (fixtures/story/...) prove
// the pipeline runs on real text but cannot prove a particular detection
// holds, because their ground truth is informal (a README ledger). These
// tests provide the formal ground truth.

///|
/// Build a SourceDoc inline.
fn make_source(rel : String, kind : SourceKind, content : String) -> SourceDoc {
  SourceDoc::new(rel, rel, kind, content)
}

///|
/// Build a ProseDoc inline.
fn make_prose(rel : String, content : String) -> ProseDoc {
  ProseDoc::new(rel, rel, content)
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
test "out-of-source: prose-only proper noun is detected (English)" {
  // The supply side mentions only the protagonist Aldous and his sister.
  // The prose introduces a butler "Parkinson" — a name with no source
  // provenance. This is the canonical drift case: a character introduced
  // at the prose layer that the writer never declared in the cast list.
  let sources = [
    make_source(
      "sources/plot/01-outline.md",
      Plot,
      "Act 1: Aldous returns to the manor. Act 2: Aldous quarrels with his sister Margaret. Act 3: Aldous departs.",
    ),
    make_source(
      "sources/references/characters.md",
      Reference,
      "Aldous is the protagonist. Margaret is his sister. They have known each other for thirty years.",
    ),
    make_source(
      "sources/references/settings.md",
      Reference,
      "The manor sits on a windswept moor. The hall has wooden panelling and a vaulted ceiling.",
    ),
  ]
  let prose = [
    make_prose(
      "prose/01-chapter.txt",
      "Aldous walked into the hall. Parkinson the butler bowed. Margaret was already waiting by the fireplace.",
    ),
    make_prose(
      "prose/02-chapter.txt",
      "Parkinson served the tea while Aldous and Margaret argued about the inheritance.",
    ),
  ]
  let dataset = StoryDataset::new("/test", sources, prose)
  let config = StoryConfig::new("/test", max_terms=50, min_value_length=2)
  let report = analyze_story(dataset, config)
  // Parkinson is the seeded out-of-source term.
  assert_true(out_contains(report, "parkinson"))
}

///|
test "under-coverage: source-only motif is detected (English)" {
  // The supply side promises a "lighthouse" as a recurring motif and a
  // "telegram" that arrives in act 2. The prose, perhaps by oversight,
  // never mentions either. The engine must surface them as gaps so the
  // writer can decide whether to weave them in or revise the plan.
  let sources = [
    make_source(
      "sources/plot/01-outline.md",
      Plot,
      "Act 1: introduction at the lighthouse. Act 2: a fateful telegram arrives. Act 3: confrontation.",
    ),
    make_source(
      "sources/plot/02-revision.md",
      Plot,
      "The lighthouse remains the central image; the telegram should be visible on the desk in every scene.",
    ),
    make_source(
      "sources/references/characters.md",
      Reference,
      "Captain Halloway runs the lighthouse. His daughter is named Ophelia.",
    ),
  ]
  let prose = [
    make_prose(
      "prose/01-chapter.txt",
      "Captain Halloway poured the brandy and watched the rain through the window. Ophelia stood by the door, silent.",
    ),
    make_prose(
      "prose/02-chapter.txt",
      "Halloway crossed the room. Ophelia would not meet his eye. The clock struck nine.",
    ),
  ]
  let dataset = StoryDataset::new("/test", sources, prose)
  let config = StoryConfig::new("/test", max_terms=50, min_value_length=2)
  let report = analyze_story(dataset, config)
  // Both seeded under-coverage terms must surface.
  assert_true(under_contains(report, "lighthouse"))
  assert_true(under_contains(report, "telegram"))
}

///|
test "out-of-source: prose-only object is detected (Japanese CJK bigrams)" {
  // 日本語コーパスで本文側にだけ登場する名詞「銀懐中」を仕込む。
  // sources は plot 二稿と人物表で、いずれにも現れない。
  // CJK 経路（character bigrams）が機能していることの確認も兼ねる。
  let sources = [
    make_source(
      "sources/plot/01-outline.md",
      Plot,
      "第一幕：青年が東京の下宿屋に到着する。第二幕：師匠と再会する。第三幕：別れを告げる。",
    ),
    make_source(
      "sources/plot/02-revision.md",
      Plot,
      "改稿。第一幕で青年は柳行李を抱えている。第二幕で師匠は煎茶を勧める。",
    ),
    make_source(
      "sources/references/characters.md",
      Reference,
      "青年は二十二歳の書生。師匠は五十がらみの漢学者で、白い顎髭を蓄えている。",
    ),
  ]
  let prose = [
    make_prose(
      "prose/01-chapter.txt",
      "青年は下宿屋の門前に立ち、懐から銀懐中を取り出して時刻を確かめた。下宿屋の女将が出迎えた。",
    ),
    make_prose(
      "prose/02-chapter.txt",
      "師匠の書斎に通された青年は、銀懐中を懐に戻し、煎茶の湯気を見つめていた。",
    ),
  ]
  let dataset = StoryDataset::new("/test", sources, prose)
  let config = StoryConfig::new("/test", max_terms=50, min_value_length=2)
  let report = analyze_story(dataset, config)
  // KGF Japanese 漢字トークンは連続漢字を1トークンに切り出すため、
  // 「銀懐中」が丸ごと1トークンとして登場する。同様に短い構成要素
  // 「銀懐」「懐中」が現れる可能性もあるが、spec が連続漢字優先のため
  // 通常は full word が優先される。いずれにせよ何らかの形で out_of_source に
  // 「銀懐中」関連語が残ればテストは通る。
  let detected = out_contains(report, "銀懐中") ||
    out_contains(report, "銀懐") ||
    out_contains(report, "懐中")
  assert_true(detected)
}

///|
test "under-coverage: source-only Japanese motif is detected (CJK bigrams)" {
  // 資料側が「白椿」を象徴として指定するが、本文には登場しない欠落ケース。
  let sources = [
    make_source(
      "sources/plot/01-outline.md",
      Plot,
      "第一幕：庭園の白椿が散り始める。第二幕：白椿の下で約束が交わされる。",
    ),
    make_source(
      "sources/references/settings.md",
      Reference,
      "庭園には白椿の木が数本ある。白椿は物語全体を貫く象徴である。",
    ),
    make_source(
      "sources/references/characters.md",
      Reference,
      "令嬢は十八歳。礼儀作法に厳しく育てられた。",
    ),
  ]
  let prose = [
    make_prose(
      "prose/01-chapter.txt",
      "令嬢は庭園を歩いた。風が冷たかった。彼女は何も言わず立ち止まった。",
    ),
    make_prose(
      "prose/02-chapter.txt",
      "令嬢は再び庭園に出た。空はどんよりと曇っていた。",
    ),
  ]
  let dataset = StoryDataset::new("/test", sources, prose)
  let config = StoryConfig::new("/test", max_terms=50, min_value_length=2)
  let report = analyze_story(dataset, config)
  let detected = under_contains(report, "白椿") || under_contains(report, "椿")
  assert_true(detected)
}

///|
test "negative control: terms shared by both sides do not appear as gaps" {
  // 全文書に共通して登場する語が gap list に紛れ込まないことを確認する。
  // これは ubiquity フィルタの陰性確認であり、陽性検出と対をなす。
  let sources = [
    make_source(
      "sources/plot/01-outline.md",
      Plot,
      "Halloway visits the harbour. Halloway speaks with the harbour-master. Halloway leaves the harbour.",
    ),
    make_source(
      "sources/references/characters.md",
      Reference,
      "Halloway is a captain. The harbour is his domain.",
    ),
  ]
  let prose = [
    make_prose(
      "prose/01-chapter.txt",
      "Halloway walked along the harbour. The wind pulled at his coat. The harbour was silent.",
    ),
    make_prose(
      "prose/02-chapter.txt",
      "Halloway looked back at the harbour. He had not slept.",
    ),
  ]
  let dataset = StoryDataset::new("/test", sources, prose)
  let config = StoryConfig::new("/test", max_terms=50, min_value_length=2)
  let report = analyze_story(dataset, config)
  // "halloway" と "harbour" はどちらにも頻出するため gap になってはならない。
  assert_false(under_contains(report, "halloway"))
  assert_false(under_contains(report, "harbour"))
  assert_false(out_contains(report, "halloway"))
  assert_false(out_contains(report, "harbour"))
}
