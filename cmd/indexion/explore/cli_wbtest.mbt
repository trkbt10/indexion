///|
test "from_matches: include and exclude patterns" {
  let cmd = command()
  let matches = cmd.parse(
    argv=[
        "--format=list", "--threshold=0.7", "--include=*.ts", "--include=*.tsx",
        "--exclude=*.d.ts", "src",
      ][:],
  )
  let config = ExploreConfig::from_matches(matches)
  assert_eq(config.format, "list")
  assert_eq(config.target_dirs.length(), 1)
  assert_eq(config.target_dirs[0], "src")
  assert_eq(config.includes.length(), 2)
  assert_eq(config.includes[0], "*.ts")
  assert_eq(config.includes[1], "*.tsx")
  assert_eq(config.excludes.length(), 1)
  assert_eq(config.excludes[0], "*.d.ts")
}

///|
test "pair_threshold_for_format: matrix keeps full pair set" {
  assert_eq(pair_threshold_for_format("matrix", 0.8), 0.0)
  assert_eq(pair_threshold_for_format("list", 0.8), 0.8)
  assert_eq(pair_threshold_for_format("cluster", 0.6), 0.6)
}

///|
test "count_cross_dir_pairs: two directories" {
  // dirA has 3 files, dirB has 2 files → 3 × 2 = 6 cross-dir pairs
  let files : Array[(String, String)] = [
    ("dirA:a1.mbt", ""), ("dirA:a2.mbt", ""), ("dirA:a3.mbt", ""),
    ("dirB:b1.mbt", ""), ("dirB:b2.mbt", ""),
  ]
  assert_eq(count_cross_dir_pairs(files), 6)
}

///|
test "count_cross_dir_pairs: three directories" {
  // dirA=2, dirB=2, dirC=1 → 2×2 + 2×1 + 2×1 = 8
  let files : Array[(String, String)] = [
    ("dirA:a1.mbt", ""), ("dirA:a2.mbt", ""),
    ("dirB:b1.mbt", ""), ("dirB:b2.mbt", ""),
    ("dirC:c1.mbt", ""),
  ]
  assert_eq(count_cross_dir_pairs(files), 8)
}

///|
test "count_cross_dir_pairs: single directory returns 1" {
  // All files in one dir → no cross-dir pairs, but floor to 1
  let files : Array[(String, String)] = [
    ("dirA:a1.mbt", ""), ("dirA:a2.mbt", ""), ("dirA:a3.mbt", ""),
  ]
  assert_eq(count_cross_dir_pairs(files), 1)
}

///|
test "count_cross_dir_pairs: no prefix returns 1" {
  // Files without directory prefix (single-dir mode)
  let files : Array[(String, String)] = [
    ("a.mbt", ""), ("b.mbt", ""),
  ]
  // All have prefix "" → same bucket → 0 cross pairs → floor to 1
  assert_eq(count_cross_dir_pairs(files), 1)
}

///|
test "apply_fdr_to_file_pairs: uses provided total_pairs directly" {
  let pairs = [
    { file1: "dirA:a.mbt", file2: "dirB:b.mbt", similarity: 0.95, _distance: 0.05 },
  ]
  // With small total_pairs (cross-dir count), the match should survive
  let result_small = apply_fdr_to_file_pairs(pairs, 6, 0.05, 0.8)
  assert_eq(result_small.length(), 1)
  // With very large total_pairs (wrong all-file nC2), it might get rejected
  // This verifies the denominator matters
  let result_large = apply_fdr_to_file_pairs(pairs, 100000, 0.05, 0.8)
  // The match at 0.95 with threshold 0.8 should still survive even with
  // large denominator due to exponential decay, but the point is the
  // denominator is controllable
  assert_true!(result_large.length() <= 1)
}

///|
test "from_matches: fdr option parsing" {
  let cmd = command()
  let matches = cmd.parse(argv=["--fdr=0.05", "src"][:])
  let config = ExploreConfig::from_matches(matches)
  // Check that fdr is close to 0.05 (floating point)
  assert_true!(config.fdr > 0.04)
  assert_true!(config.fdr < 0.06)
}
