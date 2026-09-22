///|
fn fixture_root() -> String {
  @kgf_fixtures.get_fixtures_dir() + "/project/webidl-vocabulary"
}

///|
fn fixture_specs_dir() -> String {
  @kgf_fixtures.get_kgfs_dir()
}

///|
let shared_test_registry : @kgf_registry.KGFRegistry = @kgf_features.load_registry_or_empty(
  specs_dirs=[fixture_specs_dir()],
  target_dir=fixture_root(),
)

///|
fn test_build_report(config : VocabularyConfig) -> VocabularyReport? {
  build_report_with_registry(config, shared_test_registry)
}

///|
fn fixture_config(target_name : String) -> VocabularyConfig {
  {
    ..VocabularyConfig::default(),
    source_paths: [fixture_root() + "/spec/dom.idl"],
    target_paths: [fixture_root() + "/src/conformance/" + target_name],
    specs_dirs: [fixture_specs_dir()],
  }
}

///|
test "spec-vocabulary: WebIDL fixture preserves conformance semantics" {
  let report = test_build_report(fixture_config("conformance.mbt")).unwrap()
  assert_true(report.passed)
  assert_eq(report.source_required_count, 4)
  assert_eq(report.missing_source_terms.length(), 0)
  assert_eq(report.target_drift_terms.length(), 0)
}

///|
test "spec-vocabulary: reports untracked interfaces and invented members" {
  let report = test_build_report(fixture_config("conformance_drift.mbt")).unwrap()
  assert_false(report.passed)
  assert_true(
    report.missing_source_terms.any(fn(term) {
      term.key == "interface:eventlistener"
    }),
  )
  assert_true(
    report.target_drift_terms.any(fn(term) { term.key == "member:inventedname" }),
  )
}

///|
test "spec-vocabulary: EBNF source can be checked against MoonBit targets" {
  let report = test_build_report({
    ..VocabularyConfig::default(),
    source_paths: [fixture_root() + "/spec/xpath.ebnf"],
    target_paths: [fixture_root() + "/src/xpath_lexer.mbt"],
    specs_dirs: [fixture_specs_dir()],
    direction: direction_source_to_target,
  }).unwrap()
  assert_true(report.passed)
  assert_true(
    report.source_required_terms.any(fn(term) { term.key == "symbol:axisname" }),
  )
  assert_true(
    report.source_required_terms.any(fn(term) { term.key == "literal:ancestor" }),
  )
}

///|
test "spec-vocabulary: generic KGF features cover markdown sources" {
  let report = test_build_report({
    ..VocabularyConfig::default(),
    source_paths: [fixture_root() + "/spec/terms.md"],
    target_paths: [fixture_root() + "/src/terms.md"],
    specs_dirs: [fixture_specs_dir()],
    direction: direction_source_to_target,
  }).unwrap()
  assert_true(report.passed)
  assert_true(
    report.source_required_terms.any(fn(term) { term.key == "symbol:alphabeta" }),
  )
  assert_true(
    report.source_required_terms.any(fn(term) {
      term.key == "symbol:createnode"
    }),
  )
}

///|
test "spec-vocabulary: assessments separate raw miss from report precision" {
  let report = test_build_report({
    ..VocabularyConfig::default(),
    source_paths: [fixture_root() + "/spec/trace.ebnf"],
    target_paths: [fixture_root() + "/src/trace.mbt"],
    specs_dirs: [fixture_specs_dir()],
    direction: direction_source_to_target,
  }).unwrap()
  assert_false(report.passed)
  assert_true(report.report_precision_candidate_count > 0)
  assert_eq(report.unresolved_issue_count, 0)
  assert_true(
    report.missing_source_assessments.any(fn(item) {
      item.term.key == "symbol:orexpr" &&
      item.classification == issue_classification_report_precision
    }),
  )
}

///|
test "spec-vocabulary: renderer output is generic" {
  let report = test_build_report(fixture_config("conformance.mbt")).unwrap()
  let text = render_output(report, "text")
  assert_true(text.contains("VOCABULARY CHECK: PASS"))
  let json = render_output(report, output_format_json)
  assert_true(json.contains("\"" + vocabulary_report_version + "\""))
  let md = render_output(report, output_format_markdown)
  assert_true(md.contains("# Vocabulary Check"))
}
