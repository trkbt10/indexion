///|
fn orient_entry_fixture_root(name : String) -> String {
  "/tmp/indexion-orient-entry/" + name
}

///|
fn orient_entry_config(name : String, no_update : Bool) -> AgentOrientConfig {
  let root = orient_entry_fixture_root(name)
  {
    task: "orient vcdb implementation cache workflow",
    paths: [root + "/repo"],
    specs_dir: "./kgfs",
    cache_dir: root + "/cache",
    wiki_dir: root + "/wiki",
    no_update,
    limit: 4,
    quiet: true,
    rescan: false,
  }
}

///|
async fn reset_orient_entry_fixture(name : String) -> Unit {
  @async_fs.rmdir(orient_entry_fixture_root(name), recursive=true) catch {
    _ => ()
  }
}

///|
fn write_orient_entry_file(path : String, content : String) -> Unit raise {
  @config_paths.ensure_parent_dir(path)
  @fs.write_string_to_file(path, content) catch {
    @fs.IOError(message) =>
      fail("failed to write orient entry fixture `" + path + "`: " + message)
  }
}

///|
fn seed_orient_entry_repo(config : AgentOrientConfig) -> Unit raise {
  let root = config.paths[0]
  write_orient_entry_file(
    root + "/src/orient/cache_impl.mbt",
    (
      #|/// vcdb orient cache implementation owner
      #|pub fn update_orient_cache() -> String {
      #|  "incremental implementation cache writer lock vocabulary query report"
      #|}
      #|
    ),
  )
  write_orient_entry_file(
    root + "/cmd/orient_cli.mbt",
    (
      #|/// command consumer for orient reports
      #|pub fn render_orient_cli() -> String {
      #|  "consumer cli markdown json orientation brief"
      #|}
      #|
    ),
  )
  write_orient_entry_file(
    root + "/docs/orient-cache.md",
    (
      #|# Orient Cache
      #|
      #|The orient cache documentation explains writer locking, vocabulary reuse,
      #|incremental updates, read-only queries, and report composition.
      #|
    ),
  )
}

///|
fn orient_entry_vcdb_path(config : AgentOrientConfig, leaf : String) -> String {
  config.cache_dir + "/orient-vcdb/" + leaf
}

///|
fn orient_entry_path_exists(path : String) -> Bool {
  @fs.path_exists(path)
}

///|
fn assert_orient_entry_vcdb_layout_exists(
  config : AgentOrientConfig,
) -> Unit raise {
  assert_true(
    orient_entry_path_exists(orient_entry_vcdb_path(config, "metadata.json")),
  )
  assert_true(
    orient_entry_path_exists(
      orient_entry_vcdb_path(config, "tfidf-vocabulary.json"),
    ),
  )
  assert_true(orient_entry_path_exists(orient_entry_vcdb_path(config, "vcdb")))
}

///|
fn assert_orient_entry_cache_unwritten(
  config : AgentOrientConfig,
) -> Unit raise {
  assert_false(
    orient_entry_path_exists(orient_entry_vcdb_path(config, "metadata.json")),
  )
  assert_false(
    orient_entry_path_exists(
      orient_entry_vcdb_path(config, "tfidf-vocabulary.json"),
    ),
  )
  assert_false(orient_entry_path_exists(orient_entry_vcdb_path(config, "vcdb")))
  assert_false(orient_entry_path_exists(orient_map_path(config)))
}

///|
fn write_orient_entry_stale_vocabulary_with_invalid_metadata(
  config : AgentOrientConfig,
) -> Unit raise {
  let root = config.cache_dir + "/orient-vcdb"
  @config_paths.ensure_dir_recursive(root)
  write_orient_entry_file(
    root + "/metadata.json",
    "{\n" +
    "  \"cache_version\": \"agent-orient-map-v1\",\n" +
    "  \"schema_version\": 1,\n" +
    "  \"dim\": 256,\n" +
    "  \"created_by\": \"legacy\"\n" +
    "}\n",
  )
  write_orient_entry_file(
    root + "/tfidf-vocabulary.json",
    "{ \"dim\": 256, " +
    "\"vocabulary\": [{ \"t\": \"staleonlytoken\", \"i\": 0 }], " +
    "\"idf\": [{ \"t\": \"staleonlytoken\", \"v\": 1.0 }] }\n",
  )
}

///|
async fn expect_orient_entry_writer_conflict(
  config : AgentOrientConfig,
  expected_path : String,
) -> Unit {
  try {
    let _report = orient_agent(config)
    fail("expected orient entry update to raise writer lock conflict")
  } catch {
    @cache.WriterAlreadyActive(path) => assert_eq(path, expected_path)
    err => raise err
  }
}

///|
async fn expect_orient_entry_cache_unavailable(
  config : AgentOrientConfig,
) -> Unit {
  try {
    let _report = orient_agent(config)
    fail("expected orient entry read-only mode to raise cache unavailable")
  } catch {
    @cache.Unavailable(_) => ()
    err => raise err
  }
}

///|
async test "orient entry: update mode builds fresh vcdb cache and query report" {
  let name = "update-fresh"
  reset_orient_entry_fixture(name)
  let config = orient_entry_config(name, false)
  seed_orient_entry_repo(config)
  let report = orient_agent(config)
  assert_eq(report.task, config.task)
  assert_orient_entry_vcdb_layout_exists(config)
  assert_false(orient_entry_path_exists(orient_map_path(config)))
  assert_true(report.map_status.total_files > 0)
  assert_true(report.likely_owners.length() > 0)
  let second_report = orient_agent(config)
  assert_eq(second_report.map_status.total_files, report.map_status.total_files)
  assert_eq(second_report.map_status.new_files.length(), 0)
  assert_eq(second_report.map_status.changed_files.length(), 0)
  assert_eq(second_report.map_status.deleted_files.length(), 0)
}

///|
async test "orient entry: invalid metadata rebuilds provider from current briefs" {
  let name = "update-invalid-metadata-stale-vocabulary"
  reset_orient_entry_fixture(name)
  let config = orient_entry_config(name, false)
  seed_orient_entry_repo(config)
  write_orient_entry_file(
    config.paths[0] + "/src/orient/current_provider_signal.mbt",
    (
      #|/// currentfreshneedle currentfreshneedle currentfreshneedle
      #|pub fn current_provider_signal() -> String {
      #|  "currentfreshneedle"
      #|}
      #|
    ),
  )
  write_orient_entry_stale_vocabulary_with_invalid_metadata(config)
  let report = orient_agent(config)
  assert_true(report.map_status.total_files > 0)
  let vocabulary = @fs.read_file_to_string(
    orient_entry_vcdb_path(config, "tfidf-vocabulary.json"),
  ) catch {
    _ => fail("expected rebuilt vocabulary to be readable")
  }
  assert_true(vocabulary.contains("currentfreshneedle"))
  assert_false(vocabulary.contains("staleonlytoken"))
}

///|
async test "orient entry: update mode refuses mutation without writer lock" {
  let name = "update-lock-conflict"
  reset_orient_entry_fixture(name)
  let config = orient_entry_config(name, false)
  seed_orient_entry_repo(config)
  let lock = @cache.try_acquire_writer_lock(config)
  expect_orient_entry_writer_conflict(config, @cache.writer_lock_path(config))
  assert_orient_entry_cache_unwritten(config)
  lock.release()
}

///|
async test "orient entry: read-only mode queries existing cache without writer lock" {
  let name = "read-only-existing"
  reset_orient_entry_fixture(name)
  let update_config = orient_entry_config(name, false)
  seed_orient_entry_repo(update_config)
  let update_report = orient_agent(update_config)
  let read_config = { ..update_config, no_update: true }
  let lock = @cache.try_acquire_writer_lock(update_config)
  let read_report = orient_agent(read_config)
  lock.release()
  assert_eq(read_report.task, update_report.task)
  assert_eq(
    read_report.map_status.total_files,
    update_report.map_status.total_files,
  )
  assert_false(orient_entry_path_exists(orient_map_path(update_config)))
}

///|
async test "orient entry: read-only invalid cache does not rebuild or write" {
  let name = "read-only-invalid"
  reset_orient_entry_fixture(name)
  let config = orient_entry_config(name, true)
  seed_orient_entry_repo(config)
  expect_orient_entry_cache_unavailable(config)
  assert_orient_entry_cache_unwritten(config)
  assert_false(orient_entry_path_exists(@cache.writer_lock_path(config)))
}
