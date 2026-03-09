///|
test "parse_explore_args: include and exclude patterns" {
  let config = parse_explore_args(
    [
      "--format=list", "--threshold=0.7", "--include=*.ts", "--include=*.tsx", "--exclude=*.d.ts",
      "src",
    ],
    0,
  )
  assert_eq(config.format, "list")
  assert_eq(config.target_dir, "src")
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
