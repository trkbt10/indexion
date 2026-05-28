///|
/// Build the fixture used by cobertura tests.
fn fixture() -> @coverage.CoverageReport {
  let mod_a : @coverage.FileCoverage = {
    path: "src/a/foo.mbt",
    pkg: "src/a",
    lines: [{ line: 1, hits: 1 }, { line: 4, hits: 1 }, { line: 7, hits: 0 }],
    functions: [
      { line: 1, name: "foo", hits: 1 },
      { line: 4, name: "bar", hits: 1 },
      { line: 7, name: "baz", hits: 0 },
    ],
    branches: [
      { line: 4, block: 0, branch: 0, taken: 3 },
      { line: 4, block: 0, branch: 1, taken: 0 },
      { line: 7, block: 0, branch: 0, taken: -1 },
    ],
  }
  let mod_b : @coverage.FileCoverage = {
    path: "src/b/quux.mbt",
    pkg: "src/b",
    lines: [{ line: 2, hits: 1 }, { line: 3, hits: 1 }],
    functions: [],
    branches: [],
  }
  let orphan : @coverage.FileCoverage = {
    path: "indexion.mbt",
    pkg: "",
    lines: [{ line: 1, hits: 0 }],
    functions: [],
    branches: [],
  }
  @coverage.CoverageReport::new(
    [mod_a, mod_b, orphan],
    test_name="indexion-cov",
    source_root="/repo/root",
    timestamp=1700000000L,
  )
}

///|
test "cobertura: emits root attributes from report totals" {
  let report = fixture()
  let xml = render_cobertura(report)
  assert_true(xml.has_prefix("<?xml version=\"1.0\" ?>\n"))
  assert_true(
    xml.contains(
      "<!DOCTYPE coverage SYSTEM \"http://cobertura.sourceforge.net/xml/coverage-04.dtd\">",
    ),
  )
  // lines-covered=4, lines-valid=6, branches-covered=1, branches-valid=3
  assert_true(xml.contains("lines-covered=\"4\""))
  assert_true(xml.contains("lines-valid=\"6\""))
  assert_true(xml.contains("branches-covered=\"1\""))
  assert_true(xml.contains("branches-valid=\"3\""))
  assert_true(xml.contains("timestamp=\"1700000000\""))
  assert_true(xml.contains("<source>/repo/root</source>"))
}

///|
test "cobertura: groups files by pkg and uses (default) for empty pkg" {
  let xml = render_cobertura(fixture())
  assert_true(xml.contains("<package name=\"src/a\""))
  assert_true(xml.contains("<package name=\"src/b\""))
  assert_true(xml.contains("<package name=\"(default)\""))
  // The class name is derived from the file stem, the filename keeps the
  // full relative path.
  assert_true(xml.contains("<class name=\"foo\" filename=\"src/a/foo.mbt\""))
  assert_true(xml.contains("<class name=\"quux\" filename=\"src/b/quux.mbt\""))
  assert_true(
    xml.contains("<class name=\"indexion\" filename=\"indexion.mbt\""),
  )
}

///|
test "cobertura: line rate is formatted as fixed 4-decimal string" {
  let xml = render_cobertura(fixture())
  // Whole-report line-rate = 4/6 = 0.6666… → rounded to 0.6667
  assert_true(xml.contains("line-rate=\"0.6667\""))
  // Whole-report branch-rate = 1/3 = 0.3333… → 0.3333
  assert_true(xml.contains("branch-rate=\"0.3333\""))
}

///|
test "cobertura: branch lines carry condition-coverage and branch=true" {
  let xml = render_cobertura(fixture())
  // Line 4 of mod_a has 2 branches (one taken, one not) → 1/2 = 50%
  assert_true(
    xml.contains(
      "<line number=\"4\" hits=\"1\" branch=\"true\" condition-coverage=\"50% (1/2)\"/>",
    ),
  )
  // Line 1 has no branches → branch="false"
  assert_true(xml.contains("<line number=\"1\" hits=\"1\" branch=\"false\"/>"))
}

///|
test "cobertura: empty methods and lines render as self-closing tags" {
  let empty : @coverage.FileCoverage = {
    path: "empty.mbt",
    pkg: "core",
    lines: [],
    functions: [],
    branches: [],
  }
  let xml = render_cobertura(@coverage.CoverageReport::new([empty]))
  assert_true(xml.contains("<methods/>"))
  assert_true(xml.contains("<lines/>"))
  // 0/0 → 1.0 by the empty-unit convention.
  assert_true(xml.contains("line-rate=\"1.0000\""))
}

///|
test "cobertura: escapes xml special characters in attributes" {
  let file : @coverage.FileCoverage = {
    path: "a&b/<c>.mbt",
    pkg: "weird\"pkg'",
    lines: [{ line: 1, hits: 1 }],
    functions: [],
    branches: [],
  }
  let xml = render_cobertura(@coverage.CoverageReport::new([file]))
  assert_true(xml.contains("filename=\"a&amp;b/&lt;c&gt;.mbt\""))
  assert_true(xml.contains("name=\"weird&quot;pkg&apos;\""))
}
