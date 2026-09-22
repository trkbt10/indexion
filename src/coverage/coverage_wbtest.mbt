///|
/// IR-level tests. Format-specific tests live in `src/formats/lcov/` and
/// `src/formats/cobertura/` — this file exercises only the data shapes
/// (CoverageReport, ScanResult) that those writers consume.

///|
/// Small fixture used by totals tests. Mirrors the more elaborate fixture
/// in the format packages so divergence is easy to spot.
fn fixture() -> CoverageReport {
  let mod_a : FileCoverage = {
    path: "src/a/foo.mbt",
    pkg: "src/a",
    lines: [{ line: 1, hits: 1, }, { line: 4, hits: 1, }, { line: 7, hits: 0, }],
    functions: [
      { line: 1, name: "foo", hits: 1, },
      { line: 4, name: "bar", hits: 1, },
      { line: 7, name: "baz", hits: 0, },
    ],
    branches: [
      { line: 4, block: 0, branch: 0, taken: 3, },
      { line: 4, block: 0, branch: 1, taken: 0, },
      { line: 7, block: 0, branch: 0, taken: -1, },
    ],
  }
  let mod_b : FileCoverage = {
    path: "src/b/quux.mbt",
    pkg: "src/b",
    lines: [{ line: 2, hits: 1, }, { line: 3, hits: 1, }],
    functions: [],
    branches: [],
  }
  CoverageReport::new(
    [mod_a, mod_b],
    test_name="indexion-cov",
    source_root="/repo/root",
    timestamp=1700000000L,
  )
}

///|
test "totals: per-file aggregate is correct" {
  let report = fixture()
  let mod_a = report.files[0]
  let totals = mod_a.totals()
  assert_eq(totals.lines_found, 3)
  assert_eq(totals.lines_hit, 2)
  assert_eq(totals.functions_found, 3)
  assert_eq(totals.functions_hit, 2)
  assert_eq(totals.branches_found, 3)
  assert_eq(totals.branches_hit, 1) // only `taken=3` counts as hit
}

///|
test "totals: whole-report aggregate is correct" {
  let report = fixture()
  let totals = report.totals()
  assert_eq(totals.lines_found, 5) // 3 + 2
  assert_eq(totals.lines_hit, 4) // 2 + 2
  assert_eq(totals.functions_found, 3)
  assert_eq(totals.functions_hit, 2)
  assert_eq(totals.branches_found, 3)
  assert_eq(totals.branches_hit, 1)
}

///|
test "coverage_rate: empty unit is fully covered" {
  assert_eq(coverage_rate(0, 0), 1.0)
  assert_eq(coverage_rate(1, 2), 0.5)
  assert_eq(coverage_rate(2, 2), 1.0)
}

///|
test "sort_lines: ascending by line number, stable copy" {
  let original : Array[LineHit] = [
    { line: 5, hits: 1, },
    { line: 2, hits: 0, },
    { line: 9, hits: 1, },
  ]
  let sorted = sort_lines(original)
  assert_eq(sorted[0].line, 2)
  assert_eq(sorted[1].line, 5)
  assert_eq(sorted[2].line, 9)
  // Original is not mutated.
  assert_eq(original[0].line, 5)
}

///|
test "scan: passed units become hits=1, failed units hits=0" {
  let sr = ScanResult::new("test", "/root")
  let f = ScanFile::new("a.mbt", pkg="pkg/a")
  f.add(ScanUnit::new(1, true))
  f.add(ScanUnit::new(2, false))
  sr.add_file(f)
  let report = sr.to_coverage_report()
  assert_eq(report.files.length(), 1)
  let lines = report.files[0].lines
  assert_eq(lines.length(), 2)
  assert_eq(lines[0].line, 1)
  assert_eq(lines[0].hits, 1)
  assert_eq(lines[1].line, 2)
  assert_eq(lines[1].hits, 0)
}

///|
test "scan: function units emit FunctionHit when name is non-empty" {
  let sr = ScanResult::new("test", "/root")
  let f = ScanFile::new("a.mbt", pkg="p")
  f.add(ScanUnit::new(1, true, name="foo", is_function=true))
  // is_function=true but empty name: no FunctionHit
  f.add(ScanUnit::new(2, false, is_function=true))
  // name set but is_function=false: no FunctionHit
  f.add(ScanUnit::new(3, false, name="bar"))
  sr.add_file(f)
  let report = sr.to_coverage_report()
  let funcs = report.files[0].functions
  assert_eq(funcs.length(), 1)
  assert_eq(funcs[0].name, "foo")
  assert_eq(funcs[0].hits, 1)
}

///|
test "scan: same-line units merge via max hits (pass wins)" {
  let sr = ScanResult::new("test", "/root")
  let f = ScanFile::new("a.mbt")
  // Two units at line 10: one failed, one passed → line is covered.
  f.add(ScanUnit::new(10, false))
  f.add(ScanUnit::new(10, true))
  sr.add_file(f)
  let report = sr.to_coverage_report()
  let lines = report.files[0].lines
  assert_eq(lines.length(), 1)
  assert_eq(lines[0].line, 10)
  assert_eq(lines[0].hits, 1) // pass wins
}

///|
test "scan: test_name and source_root pass through to CoverageReport" {
  let sr = ScanResult::new("indexion-plan-unwrap", "/some/root")
  let report = sr.to_coverage_report()
  assert_eq(report.test_name, "indexion-plan-unwrap")
  assert_eq(report.source_root, "/some/root")
}

///|
test "findings: record produces uncovered units" {
  let b = ScanBuilder::new()
  b.record("a.mbt", 10, name="foo", is_function=true)
  b.record("a.mbt", 12, name="bar", is_function=true)
  let report = b.to_coverage_report("t", "/r")
  assert_eq(report.files.length(), 1)
  let f = report.files[0]
  assert_eq(f.lines.length(), 2)
  assert_eq(f.lines[0].hits, 0)
  assert_eq(f.lines[1].hits, 0)
  assert_eq(f.functions.length(), 2)
  assert_eq(f.functions[0].name, "foo")
}

///|
test "findings: ensure_file returns same ScanFile across calls" {
  let b = ScanBuilder::new()
  let f1 = b.ensure_file("x.mbt", pkg="pkg")
  let f2 = b.ensure_file("x.mbt")
  assert_eq(f1.path, f2.path)
  // First call sets pkg; second call doesn't overwrite.
  assert_eq(f1.pkg, "pkg")
  // No duplicate file in resulting ScanResult.
  assert_eq(b.to_scan_result("t", "/r").files.length(), 1)
}

///|
test "findings: file_order reflects first-seen order, not lexical" {
  let b = ScanBuilder::new()
  b.record("zzz.mbt", 1, name="z")
  b.record("aaa.mbt", 1, name="a")
  let report = b.to_coverage_report("t", "/r")
  assert_eq(report.files[0].path, "zzz.mbt")
  assert_eq(report.files[1].path, "aaa.mbt")
}

///|
test "findings: default pkg is parent dir; root files get '.'" {
  let b = ScanBuilder::new()
  b.record("src/a/foo.mbt", 1, name="foo")
  b.record("top.mbt", 1, name="bar")
  let report = b.to_coverage_report("t", "/r")
  assert_eq(report.files[0].pkg, "src/a")
  assert_eq(report.files[1].pkg, ".")
}

///|
test "builder: add_unit accepts passing units too" {
  let b = ScanBuilder::new()
  b.add_unit("a.mbt", ScanUnit::new(1, true, name="foo", is_function=true))
  b.add_unit("a.mbt", ScanUnit::new(2, false, name="bar", is_function=true))
  let report = b.to_coverage_report("t", "/r")
  let f = report.files[0]
  let totals = f.totals()
  // 1 covered, 1 uncovered.
  assert_eq(totals.lines_found, 2)
  assert_eq(totals.lines_hit, 1)
  // Both functions emitted.
  assert_eq(totals.functions_found, 2)
  assert_eq(totals.functions_hit, 1)
}

///|
test "findings: name='' suppresses FunctionHit even when is_function" {
  let b = ScanBuilder::new()
  b.record("a.mbt", 5, is_function=true)
  let report = b.to_coverage_report("t", "/r")
  assert_eq(report.files[0].functions.length(), 0)
  // The line itself still gets recorded.
  assert_eq(report.files[0].lines.length(), 1)
}

///|
test "scan: empty ScanFile renders as 100%-covered placeholder" {
  let sr = ScanResult::new("test", "/root")
  sr.add_file(ScanFile::new("clean.mbt", pkg="p"))
  let report = sr.to_coverage_report()
  assert_eq(report.files.length(), 1)
  let totals = report.files[0].totals()
  assert_eq(totals.lines_found, 0)
  assert_eq(totals.lines_hit, 0)
  // Convention: 0/0 = 1.0 (fully covered).
  assert_eq(coverage_rate(totals.lines_hit, totals.lines_found), 1.0)
}
