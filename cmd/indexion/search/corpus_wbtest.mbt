///|
fn temp_dir(label : String) -> String {
  let dir = "/tmp/indexion-search/" + label + "-" + @env.now().to_string()
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
    @config.ensure_dir_recursive(@common.substring(path, 0, last_sep))
  }
  @fs.write_string_to_file(path, content) catch {
    _ => panic()
  }
}

///|
fn fixture_root() -> String {
  let root = temp_dir("versioning")
  write_file(
    root + "/moon.mod.json",
    "{\"name\":\"indexion\",\"version\":\"0.7.0\",\"source\":\"src\"}\n",
  )
  write_file(
    root + "/scripts/sync-version.sh",
    "#!/bin/sh\nVERSION=\"$1\"\necho \"sync version ${VERSION}\"\n",
  )
  write_file(
    root + "/.github/workflows/release.yml",
    "name: release\non:\n  push:\n    tags:\n      - 'v*'\n",
  )
  write_file(
    root + "/.gitmodules",
    "[submodule \"kgfs\"]\n  path = kgfs\n  url = https://example.com/kgfs.git\n",
  )
  root
}

///|
fn code_fixture_root() -> String {
  let root = fixture_root()
  write_file(
    root + "/src/update/version.mbt",
    "///|\n/// Current version of indexion.\n/// SoT is moon.mod.json version field.\n/// Auto-synced by scripts/sync-version.sh.\npub let current_version : String = \"0.7.0\"\n",
  )
  root
}

///|
fn search_config() -> SearchConfig {
  {
    query: "version",
    paths: [],
    top_k: 20,
    min_score: 0.05,
    includes: [],
    excludes: [],
    specs_dir: "kgfs",
    files_only: false,
    json_output: false,
    filter_str: "",
  }
}

///|
fn has_document_for_source(
  docs : Array[@search_engine.SearchDocument],
  source : String,
) -> Bool {
  for doc in docs {
    if doc.source == source {
      return true
    }
  }
  false
}

///|
fn first_document_for_source(
  docs : Array[@search_engine.SearchDocument],
  source : String,
) -> @search_engine.SearchDocument? {
  for doc in docs {
    if doc.source == source {
      return Some(doc)
    }
  }
  None
}

///|
fn has_hit_source(
  hits : Array[@search_engine.SearchHit],
  source : String,
) -> Bool {
  for hit in hits {
    if hit.document.source == source {
      return true
    }
  }
  false
}

///|
test "build_corpus indexes config, workflow, shell, and gitmodules files" {
  let root = fixture_root()
  let docs = build_corpus([root], search_config())
  let moon_mod = root + "/moon.mod.json"
  let workflow = root + "/.github/workflows/release.yml"
  let script = root + "/scripts/sync-version.sh"
  let gitmodules = root + "/.gitmodules"
  assert_true(has_document_for_source(docs, moon_mod))
  assert_true(has_document_for_source(docs, workflow))
  assert_true(has_document_for_source(docs, script))
  assert_true(has_document_for_source(docs, gitmodules))
  match first_document_for_source(docs, moon_mod) {
    Some(doc) => {
      assert_eq(doc.kind, "file")
      assert_eq(doc.attrs.get("content_type"), Some("config"))
    }
    None => assert_true(false)
  }
  match first_document_for_source(docs, script) {
    Some(doc) => assert_eq(doc.attrs.get("content_type"), Some("script"))
    None => assert_true(false)
  }
}

///|
test "build_corpus indexes explicit versioning metadata file lists" {
  let root = fixture_root()
  let docs = build_corpus(
    [
      root + "/moon.mod.json",
      root + "/scripts/sync-version.sh",
      root + "/.github/workflows/release.yml",
      root + "/.gitmodules",
    ],
    search_config(),
  )
  assert_true(has_document_for_source(docs, root + "/moon.mod.json"))
  assert_true(has_document_for_source(docs, root + "/scripts/sync-version.sh"))
  assert_true(
    has_document_for_source(docs, root + "/.github/workflows/release.yml"),
  )
  assert_true(has_document_for_source(docs, root + "/.gitmodules"))
}

///|
async test "search self-host retrieval finds versioning metadata chain" {
  let _unit = @async.with_task_group(_group => ())
  let root = fixture_root()
  let docs = build_corpus([root], search_config())
  let engine = @search_engine.SearchEngine::build(docs) catch { _ => panic() }
  let hits = engine.search(
    "project version release current_version sync version",
    top_k=12,
    min_score=0.05,
  )
  assert_true(has_hit_source(hits, root + "/scripts/sync-version.sh"))
  assert_true(has_hit_source(hits, root + "/.github/workflows/release.yml"))
  assert_true(has_hit_source(hits, root + "/moon.mod.json"))
}

///|
async test "search retrieval follows code-side version SoT context" {
  let _unit = @async.with_task_group(_group => ())
  let root = code_fixture_root()
  let docs = build_corpus([root], search_config())
  let engine = @search_engine.SearchEngine::build(docs) catch { _ => panic() }
  let hits = engine.search(
    "moon.mod.json version field auto synced",
    top_k=12,
    min_score=0.05,
  )
  assert_true(has_hit_source(hits, root + "/src/update/version.mbt"))
}

///|
async test "search retrieval keeps code-side version SoT with explicit file lists" {
  let _unit = @async.with_task_group(_group => ())
  let root = code_fixture_root()
  let docs = build_corpus(
    [
      root + "/src/update/version.mbt",
      root + "/moon.mod.json",
      root + "/scripts/sync-version.sh",
      root + "/.github/workflows/release.yml",
    ],
    search_config(),
  )
  let engine = @search_engine.SearchEngine::build(docs) catch { _ => panic() }
  let hits = engine.search(
    "moon.mod.json version field auto synced",
    top_k=12,
    min_score=0.05,
  )
  assert_true(has_document_for_source(docs, root + "/moon.mod.json"))
  assert_true(has_hit_source(hits, root + "/src/update/version.mbt"))
}
