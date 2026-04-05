///|
/// Integration tests using the JSON-RPC 2.0 / RFC 7396 fixture.
///
/// Fixture: fixtures/project/spec-verify-jsonrpc/
///   spec/jsonrpc-2.0.md          — JSON-RPC 2.0 spec (markdown)
///   spec/rfc7396-merge-patch.html — RFC 7396 JSON Merge Patch (actual RFC HTML)
///   moonbit/                      — MoonBit project
///   typescript/                   — TypeScript project
///   python/                       — Python project
///
/// Tests verify that TF-IDF vocabulary comparison detects spec terms
/// absent from implementation, across multiple languages and spec formats.

///|
fn fixture_root() -> String {
  @kgf_fixtures.get_fixtures_dir() + "/project/spec-verify-jsonrpc"
}

///|
fn fixture_specs_dir() -> String {
  @kgf_fixtures.get_kgfs_dir()
}

///|
/// Build a VerifyConfig for a given language project against the markdown spec.
/// Uses empty root_dir to bypass .indexionignore (fixtures/ would be excluded).
fn fixture_config_for(lang_dir : String) -> VerifyConfig {
  {
    ..VerifyConfig::default(),
    spec_patterns: [fixture_root() + "/spec/jsonrpc-2.0.md"],
    target_dir: fixture_root() + "/" + lang_dir,
    root_dir: Some(""),
    specs_dir: fixture_specs_dir(),
  }
}

///|
/// Build a VerifyConfig using the HTML RFC spec.
fn fixture_config_html(lang_dir : String) -> VerifyConfig {
  {
    ..VerifyConfig::default(),
    spec_patterns: [fixture_root() + "/spec/rfc7396-merge-patch.html"],
    target_dir: fixture_root() + "/" + lang_dir,
    root_dir: Some(""),
    specs_dir: fixture_specs_dir(),
  }
}

// ========== Core analysis tests ==========

///|
test "spec-verify/moonbit: markdown spec produces vocabulary analysis" {
  let config = fixture_config_for("moonbit")
  let report = run_analysis(config)
  assert_true(
    report.summary.cosine_distance > 0.0,
    msg="cosine distance should be > 0 (spec and impl differ)",
  )
  assert_true(
    report.summary.spec_symbols > 0,
    msg="spec should produce tokens",
  )
}

///|
test "spec-verify/typescript: markdown spec produces gap terms" {
  let config = fixture_config_for("typescript")
  let report = run_analysis(config)
  assert_true(report.summary.impl_files > 0, msg="no .ts files found")
  assert_true(
    report.summary.cosine_distance > 0.0,
    msg="cosine distance should be > 0",
  )
}

///|
test "spec-verify/python: markdown spec produces gap terms" {
  let config = fixture_config_for("python")
  let report = run_analysis(config)
  assert_true(report.summary.impl_files > 0, msg="no .py files found")
  assert_true(
    report.summary.cosine_distance > 0.0,
    msg="cosine distance should be > 0",
  )
}

// ========== HTML RFC spec tests ==========

///|
test "spec-verify/moonbit: HTML RFC spec produces report" {
  let config = fixture_config_html("moonbit")
  let report = run_analysis(config)
  assert_true(report.summary.spec_files == 1, msg="expected 1 HTML spec file")
  assert_true(
    report.summary.impl_files > 0,
    msg="no impl files discovered",
  )
  assert_true(
    report.summary.spec_symbols > 0,
    msg="no spec symbols from HTML RFC",
  )
}

///|
test "spec-verify/typescript: HTML RFC spec produces report" {
  let config = fixture_config_html("typescript")
  let report = run_analysis(config)
  assert_true(report.summary.impl_files > 0, msg="no .ts files found")
  assert_true(report.summary.spec_symbols > 0, msg="no spec symbols from HTML")
}

///|
test "spec-verify/python: HTML RFC spec produces report" {
  let config = fixture_config_html("python")
  let report = run_analysis(config)
  assert_true(report.summary.impl_files > 0, msg="no .py files found")
  assert_true(report.summary.spec_symbols > 0, msg="no spec symbols from HTML")
}

// ========== Summary & renderer tests ==========

///|
test "spec-verify: summary fields are consistent" {
  let config = fixture_config_for("moonbit")
  let report = run_analysis(config)
  assert_eq(report.summary.gap_count, report.items.length())
  assert_eq(report.summary.missing, report.items.length())
}

///|
test "spec-verify: renderers produce valid output" {
  let config = fixture_config_for("moonbit")
  let report = run_analysis(config)
  let md = render_output(report, "md")
  assert_true(md.contains("# Spec Verify Report"))
  assert_true(md.contains("Vocabulary distance"))
  let json_out = render_output(report, "json")
  assert_true(json_out.contains("\"spec-verify-v1\""))
  let issue = render_output(report, "github-issue")
  assert_true(issue.contains("Vocabulary distance"))
}
