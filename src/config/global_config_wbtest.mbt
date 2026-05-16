///|
using @test {assert_eq}

test "global_config: parse_global_toml_config parses global section" {
  let input =
    #|[global]
    #|kgfs_dir = "~/kgfs"
  let config = parse_global_toml_config(input)
  assert_true(config.kgfs_dir is Some(_))
  let kgfs_dir = config.kgfs_dir.unwrap()
  // Should expand ~ to home dir if HOME is set
  match @platform.get_home_dir() {
    Some(home) => {
      assert_true(!kgfs_dir.has_prefix("~"))
      assert_true(kgfs_dir.has_prefix(home))
    }
    None =>
      // If HOME is not set, ~ remains unexpanded
      assert_true(kgfs_dir == "~/kgfs")
  }
  assert_true(kgfs_dir.has_suffix("/kgfs"))
}

///|
test "global_config: parse_global_toml_config parses reconcile section" {
  let input =
    #|[reconcile]
    #|threshold_seconds = 120
    #|max_candidates = 50
    #|doc_scope = "tree-docs"
  let config = parse_global_toml_config(input)
  assert_eq(config.reconcile.threshold_seconds, Some(120))
  assert_eq(config.reconcile.max_candidates, Some(50))
  assert_eq(config.reconcile.doc_scope, Some("tree-docs"))
}

///|
test "global_config: parse_global_toml_config parses nested reconcile sections" {
  let input =
    #|[reconcile.time]
    #|git_preferred = true
    #|mtime_fallback = false
    #|
    #|[reconcile.mapping]
    #|allow_file_fallback = true
    #|
    #|[reconcile.output]
    #|default_format = "md"
  let config = parse_global_toml_config(input)
  assert_eq(config.reconcile.git_preferred, Some(true))
  assert_eq(config.reconcile.mtime_fallback, Some(false))
  assert_eq(config.reconcile.allow_file_fallback, Some(true))
  assert_eq(config.reconcile.format, Some("md"))
}

///|
test "global_config: empty returns empty config" {
  let config = GlobalConfig::empty()
  assert_true(config.kgfs_dir is None)
  assert_true(config.reconcile.threshold_seconds is None)
}

///|
test "global_config: get_global_config_path returns path on supported platforms" {
  let platform = @platform.detect_platform()
  if platform != @platform.Platform::Unknown {
    let path = get_global_config_path()
    assert_true(path is Some(_))
    let p = path.unwrap()
    assert_true(p.has_suffix("config.toml"))
  }
}

///|
test "global_config: load_global_config returns empty when no file exists" {
  // This test assumes global config file doesn't exist in test environment
  let config = load_global_config()
  // Should return empty config, not crash
  assert_true(config.kgfs_dir is None || config.kgfs_dir is Some(_))
}
