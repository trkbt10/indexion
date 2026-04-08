///|
fn temp_dir(label : String) -> String {
  let dir = "/tmp/indexion-grep/" + label + "-" + @env.now().to_string()
  @config.ensure_dir_recursive(dir)
  dir
}

///|
fn write_file(path : String, content : String) -> Unit {
  let chars = path.to_array()
  let mut last_sep = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last_sep = i
    }
  }
  if last_sep > 0 {
    @config.ensure_dir_recursive(@config.substring(path, 0, last_sep))
  }
  @fs.write_string_to_file(path, content) catch {
    _ => panic()
  }
}

///|
fn fixture_root() -> String {
  let root = temp_dir("collect")
  write_file(root + "/moon.mod.json", "{\"version\":\"0.7.0\"}\n")
  write_file(root + "/scripts/sync-version.sh", "VERSION=\"$1\"\n")
  write_file(root + "/.github/workflows/release.yml", "name: release\n")
  write_file(root + "/.gitmodules", "[submodule \"kgfs\"]\n  path = kgfs\n")
  write_file(
    root + "/skills/.claude-plugin/marketplace.json",
    "{\"name\":\"plugin\",\"version\":\"0.7.0\"}\n",
  )
  root
}

///|
fn contains_file(files : Array[(String, String)], path : String) -> Bool {
  for file in files {
    if file.0 == path {
      return true
    }
  }
  false
}

///|
fn count_matches_for_pattern(
  root : String,
  pattern : String,
) -> Map[String, Int] {
  let registry = @kgf_features.load_registry_or_empty(specs_dir="kgfs", target_dirs=[
    root,
  ])
  let files = collect_search_files([root], GrepConfig::default(), registry)
  let matchers = parse_pattern(pattern)
  let counts : Map[String, Int] = {}
  for file in files {
    let (path, content) = file
    let spec = match registry.detect_from_path(path) {
      Some(lang) => registry.get_spec(lang)
      None => None
    }
    let tokens = match
      @kgf_features.tokenize_source(content, path, Some(registry)) {
      Some(value) => value
      None => continue
    }
    let matches = find_matches(tokens, matchers, path, content, spec~)
    if matches.length() > 0 {
      counts.set(path, matches.length())
    }
  }
  counts
}

///|
test "collect_search_files honors registry support for versioning metadata files" {
  let root = fixture_root()
  let registry = @kgf_features.load_registry_or_empty(specs_dir="kgfs", target_dirs=[
    root,
  ])
  let files = collect_search_files([root], GrepConfig::default(), registry)
  assert_true(contains_file(files, root + "/moon.mod.json"))
  assert_true(contains_file(files, root + "/scripts/sync-version.sh"))
  assert_true(contains_file(files, root + "/.github/workflows/release.yml"))
  assert_true(contains_file(files, root + "/.gitmodules"))
  assert_true(
    contains_file(files, root + "/skills/.claude-plugin/marketplace.json"),
  )
}

///|
test "quoted grep pattern is not normalized like unquoted text" {
  let root = fixture_root()
  let quoted = count_matches_for_pattern(root, "\"version\"")
  assert_true(quoted.contains(root + "/moon.mod.json"))
  assert_false(quoted.contains(root + "/scripts/sync-version.sh"))
  assert_false(quoted.contains(root + "/.gitmodules"))
}
