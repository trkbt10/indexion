///|
/// Build the fixture used by lcov tests.
fn fixture() -> @coverage.CoverageReport {
  let mod_a : @coverage.FileCoverage = {
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
  let mod_b : @coverage.FileCoverage = {
    path: "src/b/quux.mbt",
    pkg: "src/b",
    lines: [{ line: 2, hits: 1, }, { line: 3, hits: 1, }],
    functions: [],
    branches: [],
  }
  let orphan : @coverage.FileCoverage = {
    path: "indexion.mbt",
    pkg: "",
    lines: [{ line: 1, hits: 0, }],
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
/// Find the byte offset of `needle` in `haystack`, or -1 if absent.
fn find_substr(haystack : String, needle : String) -> Int {
  let h = haystack.to_array()
  let n = needle.to_array()
  if n.length() == 0 || h.length() < n.length() {
    return -1
  }
  for i = 0; i <= h.length() - n.length(); i = i + 1 {
    let mut matched = true
    for j = 0; j < n.length(); j = j + 1 {
      if h[i + j] != n[j] {
        matched = false
        break
      }
    }
    if matched {
      return i
    }
  }
  -1
}

///|
test "lcov: emits required record kinds in the canonical order" {
  let report = fixture()
  let out = render_lcov(report)
  // Three files → three end_of_record markers.
  let mut eor_count = 0
  let chars = out.to_array()
  let needle = "end_of_record\n".to_array()
  let mut i = 0
  while i <= chars.length() - needle.length() {
    let mut matched = true
    for j = 0; j < needle.length(); j = j + 1 {
      if chars[i + j] != needle[j] {
        matched = false
        break
      }
    }
    if matched {
      eor_count = eor_count + 1
      i = i + needle.length()
    } else {
      i = i + 1
    }
  }
  assert_eq(eor_count, 3)
  // Spot-check a known record from the first file.
  assert_true(out.contains("TN:indexion-cov\n"))
  assert_true(out.contains("SF:src/a/foo.mbt\n"))
  assert_true(out.contains("FN:1,foo\n"))
  assert_true(out.contains("FNDA:0,baz\n"))
  assert_true(out.contains("FNF:3\n"))
  assert_true(out.contains("FNH:2\n"))
  assert_true(out.contains("BRDA:4,0,0,3\n"))
  // taken=-1 must render as "-", per the lcov spec.
  assert_true(out.contains("BRDA:7,0,0,-\n"))
  assert_true(out.contains("BRF:3\n"))
  assert_true(out.contains("BRH:1\n"))
  assert_true(out.contains("DA:1,1\n"))
  assert_true(out.contains("DA:7,0\n"))
  assert_true(out.contains("LF:3\n"))
  assert_true(out.contains("LH:2\n"))
}

///|
test "lcov: lines are sorted by line number for determinism" {
  let file : @coverage.FileCoverage = {
    path: "x.mbt",
    pkg: "",
    lines: [{ line: 5, hits: 1, }, { line: 2, hits: 1, }, { line: 9, hits: 0, }],
    functions: [],
    branches: [],
  }
  let out = render_lcov(@coverage.CoverageReport::new([file]))
  let i2 = find_substr(out, "DA:2,1")
  let i5 = find_substr(out, "DA:5,1")
  let i9 = find_substr(out, "DA:9,0")
  assert_true(i2 >= 0)
  assert_true(i5 > i2)
  assert_true(i9 > i5)
}
