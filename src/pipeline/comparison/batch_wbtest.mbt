///|
/// Whitebox tests for batch comparison SoT.

///|
test "FileEntry::new creates entry" {
  let entry = FileEntry::new("test.ts", "content")
  assert_eq(entry.display_name, "test.ts")
  assert_eq(entry.content, "content")
}

///|
test "BatchConfig::new creates default config" {
  let config = BatchConfig::new()
  assert_true(config.threshold > 0.79 && config.threshold < 0.81)
  assert_eq(config.strategy, "tfidf")
}

///|
test "BatchConfig::create creates custom config" {
  let config = BatchConfig::create(0.9, "apted")
  assert_true(config.threshold > 0.89 && config.threshold < 0.91)
  assert_eq(config.strategy, "apted")
}

///|
test "SimilarityMatch::new creates match" {
  let m = SimilarityMatch::new(0, 1, "a.ts", "b.ts", 0.95)
  assert_eq(m.index1, 0)
  assert_eq(m.index2, 1)
  assert_eq(m.file1, "a.ts")
  assert_eq(m.file2, "b.ts")
  assert_true(m.similarity > 0.94 && m.similarity < 0.96)
}

///|
test "compare_tfidf with empty files returns empty" {
  let result = compare_tfidf([], 0.8)
  assert_eq(result.matches.length(), 0)
  assert_eq(result.file_count, 0)
}

///|
test "compare_tfidf with single file returns empty" {
  let files = [FileEntry::new("a.ts", "const x = 1")]
  let result = compare_tfidf(files, 0.8)
  assert_eq(result.matches.length(), 0)
  assert_eq(result.file_count, 1)
}

///|
test "compare_tfidf with similar files finds match" {
  let files = [
    FileEntry::new("a.ts", "const x = 1\nconst y = 2"),
    FileEntry::new("b.ts", "const x = 1\nconst y = 2"),
  ]
  let result = compare_tfidf(files, 0.8)
  assert_eq(result.file_count, 2)
  assert_eq(result.pairs_compared, 1)
  // Identical files should have similarity >= 0.8
  assert_true(result.matches.length() >= 1)
}

///|
test "filter_cross_directory filters same-directory pairs" {
  let matches = [
    SimilarityMatch::new(0, 1, "pkg1:a.ts", "pkg1:b.ts", 0.9),
    SimilarityMatch::new(0, 2, "pkg1:a.ts", "pkg2:c.ts", 0.85),
  ]
  let filtered = filter_cross_directory(matches)
  assert_eq(filtered.length(), 1)
  assert_eq(filtered[0].file2, "pkg2:c.ts")
}

///|
test "filter_cross_directory keeps all cross-directory pairs" {
  let matches = [
    SimilarityMatch::new(0, 1, "pkg1:a.ts", "pkg2:b.ts", 0.9),
    SimilarityMatch::new(0, 2, "pkg1:a.ts", "pkg3:c.ts", 0.85),
  ]
  let filtered = filter_cross_directory(matches)
  assert_eq(filtered.length(), 2)
}
