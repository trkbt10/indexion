///|
using @test {assert_eq}

///|
fn temp_wiki_log_dir(label : String) -> String {
  let dir = "/tmp/indexion-wiki-log/" + label + "-" + @env.now().to_string()
  @config.ensure_dir_recursive(dir)
  dir
}

///|
fn write_log_fixture(wiki_dir : String, content : String) -> Unit {
  @fs.write_string_to_file(@wiki_types.wiki_log_path(wiki_dir), content) catch {
    _ => panic()
  }
}

///|
test "WikiLog load append save preserves existing timestamp strings" {
  let wiki_dir = temp_wiki_log_dir("timestamp-roundtrip")
  write_log_fixture(
    wiki_dir,
    (
      #|[
      #|  {
      #|    "timestamp": "1778124306650",
      #|    "operation": "ingest",
      #|    "actor": "indexion",
      #|    "summary": "0 pages need attention",
      #|    "details": {},
      #|    "affected_pages": []
      #|  },
      #|  {
      #|    "timestamp": 123,
      #|    "operation": "lint",
      #|    "actor": "indexion",
      #|    "summary": "0 issues found",
      #|    "details": {},
      #|    "affected_pages": []
      #|  }
      #|]
      #|
    ),
  )
  let log = WikiLog::load(wiki_dir)
  let before = log.tail(2)
  assert_eq(before[0].timestamp, 1778124306650UL)
  assert_eq(before[1].timestamp, 123UL)
  log.append(
    WikiLogEntry::new(
      timestamp=999UL,
      operation="index build",
      actor="indexion",
      summary="Built index",
    ),
  )
  log.save(wiki_dir)
  let reloaded = WikiLog::load(wiki_dir)
  let after = reloaded.tail(3)
  assert_eq(after[0].timestamp, 1778124306650UL)
  assert_eq(after[1].timestamp, 123UL)
  assert_eq(after[2].timestamp, 999UL)
  let saved = @fs.read_file_to_string(@wiki_types.wiki_log_path(wiki_dir)) catch {
    _ => panic()
  }
  assert_true(saved.contains("\"timestamp\": \"1778124306650\""))
  assert_true(!saved.contains("\"timestamp\": \"0\""))
}
