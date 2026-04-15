///|
/// Tests for WikiSearchIndex: build, save/load round-trip, update_page,
/// and provider persistence.

///|
fn temp_wiki_dir() -> String {
  let dir = "/tmp/indexion-wiki-search/" + @env.now().to_string()
  @config.ensure_dir_recursive(dir)
  dir
}

///|
fn make_pages(
  entries : Array[(String, String, String)],
) -> Map[String, @types.WikiPage] {
  let pages : Map[String, @types.WikiPage] = {}
  for entry in entries {
    let (id, title, content) = entry
    pages[id] = @types.WikiPage::new(id~, title~, content~)
  }
  pages
}

///|
async test "build_search_index: sections extracted and searchable" {
  let _unit = @async.with_task_group(_group => ())
  let pages = make_pages([
    (
      "arch", "Architecture", "# Architecture\n\nThis describes the system architecture.\n",
    ),
    (
      "guide", "Getting Started", "# Getting Started\n\nInstall and configure the tool.\n",
    ),
  ])
  let provider = @embed_config.TfIdf(@embed_config.DEFAULT_TFIDF_DIM)
  let idx = build_search_index(pages, provider) catch { _ => panic() }
  assert_true(idx.sections.length() > 0)
  assert_true(idx.engine.size() > 0)
  assert_true(idx.next_vid > 1L)
}

///|
async test "WikiSearchIndex::search: returns relevant hit" {
  let _unit = @async.with_task_group(_group => ())
  let pages = make_pages([
    (
      "arch", "Architecture", "# Architecture\n\nThe system uses a layered architecture with vcdb.\n",
    ),
    ("guide", "Install", "# Install\n\nRun moon install to get started.\n"),
  ])
  let provider = @embed_config.TfIdf(@embed_config.DEFAULT_TFIDF_DIM)
  let idx = build_search_index(pages, provider) catch { _ => panic() }
  let hits = idx.search("system architecture vcdb", top_k=5, min_score=0.01) catch {
    _ => panic()
  }
  assert_true(hits.length() > 0)
  let top = hits[0]
  assert_true(top.section.page_id == "arch")
}

///|
async test "WikiSearchIndex save/load: round-trip preserves sections and provider" {
  let _unit = @async.with_task_group(_group => ())
  let wiki_dir = temp_wiki_dir()
  let pages = make_pages([
    ("p1", "Page One", "# Page One\n\nFirst page content about indexing.\n"),
    ("p2", "Page Two", "# Page Two\n\nSecond page about search vectors.\n"),
  ])
  let provider = @embed_config.TfIdf(@embed_config.DEFAULT_TFIDF_DIM)
  let original = build_search_index(pages, provider) catch { _ => panic() }
  original.save(wiki_dir)
  let loaded = match WikiSearchIndex::load(wiki_dir) {
    Some(idx) => idx
    None => panic()
  }
  assert_eq(loaded.sections.length(), original.sections.length())
  assert_eq(loaded.next_vid, original.next_vid)
  // Provider round-trips correctly
  match (loaded.provider, original.provider) {
    (@embed_config.TfIdf(d1), @embed_config.TfIdf(d2)) => assert_eq(d1, d2)
    _ => panic()
  }
}

///|
async test "WikiSearchIndex save/load: search still works after load" {
  let _unit = @async.with_task_group(_group => ())
  let wiki_dir = temp_wiki_dir()
  let pages = make_pages([
    (
      "concepts", "Core Concepts", "# Core Concepts\n\nEmbedding and TF-IDF are core concepts.\n",
    ),
    (
      "cli", "CLI Reference", "# CLI Reference\n\nCommand line interface documentation.\n",
    ),
  ])
  let provider = @embed_config.TfIdf(@embed_config.DEFAULT_TFIDF_DIM)
  let original = build_search_index(pages, provider) catch { _ => panic() }
  original.save(wiki_dir)
  let loaded = WikiSearchIndex::load(wiki_dir).unwrap()
  let hits = loaded.search("embedding TF-IDF", top_k=5, min_score=0.01) catch {
    _ => panic()
  }
  assert_true(hits.length() > 0)
  assert_true(hits[0].section.page_id == "concepts")
}

///|
async test "update_page: old sections removed, new sections added" {
  let _unit = @async.with_task_group(_group => ())
  let pages = make_pages([
    (
      "target", "Target Page", "# Target Page\n\nOriginal content about alpha.\n",
    ),
    ("other", "Other Page", "# Other Page\n\nUnrelated content.\n"),
  ])
  let provider = @embed_config.TfIdf(@embed_config.DEFAULT_TFIDF_DIM)
  let idx = build_search_index(pages, provider) catch { _ => panic() }
  let sections_before = idx.sections.length()
  let engine_size_before = idx.engine.size()
  // Count target page sections before update
  let mut _target_sections_before = 0
  for entry in idx.sections {
    if entry.1.page_id == "target" {
      _target_sections_before += 1
    }
  }
  // Update with entirely new content
  idx.update_page(
    "target", "Target Page", "# Target Page\n\nNew content about beta and gamma.\n",
  ) catch {
    _ => panic()
  }
  // Section count must stay the same (removed old, added new for same page)
  assert_eq(idx.sections.length(), sections_before)
  // Engine size must stay the same
  assert_eq(idx.engine.size(), engine_size_before)
  // Old content gone, new content present
  let mut has_target_after = false
  for entry in idx.sections {
    if entry.1.page_id == "target" {
      has_target_after = true
      assert_true(entry.1.content.contains("beta"))
    }
  }
  assert_true(has_target_after)
}

///|
async test "update_page: next_vid advances monotonically" {
  let _unit = @async.with_task_group(_group => ())
  let pages = make_pages([("page", "Page", "# Page\n\nContent.\n")])
  let provider = @embed_config.TfIdf(@embed_config.DEFAULT_TFIDF_DIM)
  let idx = build_search_index(pages, provider) catch { _ => panic() }
  let vid_after_build = idx.next_vid
  idx.update_page("page", "Page", "# Page\n\nNew content.\n") catch {
    _ => panic()
  }
  assert_true(idx.next_vid > vid_after_build)
}

///|
async test "update_page: updated content is searchable in-memory" {
  let _unit = @async.with_task_group(_group => ())
  let pages = make_pages([
    ("doc", "Doc", "# Doc\n\nOriginal content about search indexing.\n"),
    ("other", "Other", "# Other\n\nUnrelated content.\n"),
  ])
  let provider = @embed_config.TfIdf(@embed_config.DEFAULT_TFIDF_DIM)
  let idx = build_search_index(pages, provider) catch { _ => panic() }
  idx.update_page(
    "doc", "Doc", "# Doc\n\nUpdated content: search and indexing improved.\n",
  ) catch {
    _ => panic()
  }
  let hits = idx.search("search indexing", top_k=5, min_score=0.01) catch {
    _ => panic()
  }
  assert_true(hits.length() > 0)
  assert_true(hits[0].section.page_id == "doc")
}

///|
async test "update_page: updated content searchable after save and reload" {
  let _unit = @async.with_task_group(_group => ())
  let wiki_dir = temp_wiki_dir()
  let pages = make_pages([
    ("doc", "Doc", "# Doc\n\nOriginal content about search indexing.\n"),
    ("other", "Other", "# Other\n\nContent about search.\n"),
  ])
  let provider = @embed_config.TfIdf(@embed_config.DEFAULT_TFIDF_DIM)
  let idx = build_search_index(pages, provider) catch { _ => panic() }
  idx.update_page("doc", "Doc", "# Doc\n\nUpdated: search indexing improved.\n") catch {
    _ => panic()
  }
  idx.save(wiki_dir)
  let loaded = WikiSearchIndex::load(wiki_dir).unwrap()
  let hits = loaded.search("search indexing", top_k=5, min_score=0.01) catch {
    _ => panic()
  }
  assert_true(hits.length() > 0)
  assert_true(hits[0].section.page_id == "doc")
}
