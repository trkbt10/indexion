///|
fn temp_wiki_workspace_dir(label : String) -> String {
  let dir = "/tmp/indexion-wiki-workspace/" +
    label +
    "-" +
    @env.now().to_string()
  @config.ensure_dir_recursive(dir)
  dir
}

///|
fn write_test_file(path : String, content : String) -> Unit {
  @config.ensure_parent_dir(path)
  @fs.write_string_to_file(path, content) catch {
    _ => panic()
  }
}

///|
test "resolve wiki dir accepts direct wiki directory" {
  let wiki_dir = temp_wiki_workspace_dir("direct")
  write_test_file(
    wiki_dir + "/wiki.json",
    "{\"title\":\"Docs\",\"pages\":[]}\n",
  )
  assert_eq(resolve_wiki_dir(wiki_dir), Some(wiki_dir))
}

///|
test "resolve wiki dir preserves explicit custom path without manifest" {
  let root = temp_wiki_workspace_dir("custom")
  @config.ensure_dir_recursive(root + "/.indexion")
  let custom = root + "/custom/wiki"
  assert_eq(resolve_wiki_dir(custom), Some(custom))
}

///|
test "resolve wiki dir does not treat lookalike suffix as default wiki" {
  let root = temp_wiki_workspace_dir("lookalike")
  @config.ensure_dir_recursive(root + "/.indexion")
  let custom = root + "/docs.indexion/wiki"
  assert_eq(resolve_wiki_dir(custom), Some(custom))
}

///|
test "resolve wiki dir maps default path through project root" {
  let root = temp_wiki_workspace_dir("default")
  @config.ensure_dir_recursive(root + "/.indexion")
  assert_eq(
    resolve_wiki_dir(root + "/.indexion/wiki"),
    Some(root + "/.indexion/wiki"),
  )
}

///|
test "project wiki resolver treats input as workspace anchor" {
  let root = temp_wiki_workspace_dir("anchor")
  @config.ensure_dir_recursive(root + "/.indexion")
  @config.ensure_dir_recursive(root + "/src")
  assert_eq(
    resolve_project_wiki_dir(root + "/src"),
    Some(root + "/.indexion/wiki"),
  )
}

///|
test "wiki content paths come from manifest SoT" {
  let wiki_dir = temp_wiki_workspace_dir("paths")
  write_test_file(
    wiki_dir + "/wiki.json",
    "{\"title\":\"Docs\",\"pages\":[{\"id\":\"home\",\"title\":\"Home\",\"file\":\"home.md\",\"sources\":[],\"children\":[],\"provenance\":null,\"last_actor\":null}]}\n",
  )
  write_test_file(wiki_dir + "/home.md", "# Home\n")
  assert_eq(
    wiki_content_paths(wiki_dir),
    Some([wiki_dir + "/wiki.json", wiki_dir + "/home.md"]),
  )
}

///|
test "wiki search generated path detection" {
  assert_true(is_wiki_search_generated_path(".indexion/wiki/vectors.db"))
  assert_true(
    is_wiki_search_generated_path(".indexion/wiki/search-sections.json"),
  )
  assert_true(
    is_wiki_search_generated_path(".indexion/wiki/tfidf-vocabulary.json"),
  )
  assert_true(is_wiki_search_generated_path(".indexion/wiki/index.md"))
  assert_false(is_wiki_search_generated_path(".indexion/wiki/overview.md"))
}

///|
fn sample_manifest() -> @wiki_types.WikiManifest {
  let text = "{\"title\":\"Docs\",\"pages\":[{\"id\":\"home\",\"title\":\"Home\",\"file\":\"home.md\",\"sources\":[],\"children\":[],\"provenance\":null,\"last_actor\":null}]}"
  @json.from_json(@json.parse(text)) catch {
    _ => panic()
  }
}

///|
test "wiki update plan maps page files to incremental page ids" {
  let wiki_dir = temp_wiki_workspace_dir("plan-page")
  let plan = WikiUpdatePlan::new()
  mark_content_path_changed(
    plan,
    wiki_dir,
    sample_manifest(),
    wiki_dir + "/home.md",
  )
  assert_false(plan.full_rebuild)
  assert_true(plan.page_ids.contains("home"))
}

///|
test "wiki update plan treats manifest and unknown paths as full rebuild" {
  let wiki_dir = temp_wiki_workspace_dir("plan-full")
  let manifest = sample_manifest()
  let manifest_plan = WikiUpdatePlan::new()
  mark_content_path_changed(
    manifest_plan,
    wiki_dir,
    manifest,
    wiki_dir + "/wiki.json",
  )
  assert_true(manifest_plan.full_rebuild)
  let unknown_plan = WikiUpdatePlan::new()
  mark_content_path_changed(
    unknown_plan,
    wiki_dir,
    manifest,
    wiki_dir + "/unknown.md",
  )
  assert_true(unknown_plan.full_rebuild)
}

///|
async test "wiki search update can incrementally update one page" {
  let _unit = @async.with_task_group(_group => ())
  let wiki_dir = temp_wiki_workspace_dir("incremental")
  write_test_file(
    wiki_dir + "/wiki.json",
    "{\"title\":\"Docs\",\"pages\":[{\"id\":\"home\",\"title\":\"Home\",\"file\":\"home.md\",\"sources\":[],\"children\":[],\"provenance\":null,\"last_actor\":null},{\"id\":\"other\",\"title\":\"Other\",\"file\":\"other.md\",\"sources\":[],\"children\":[],\"provenance\":null,\"last_actor\":null}]}\n",
  )
  write_test_file(wiki_dir + "/home.md", "# Home\n\nOriginal alpha content.\n")
  write_test_file(wiki_dir + "/other.md", "# Other\n\nStable beta content.\n")
  let provider = @embed_config.TfIdf(@embed_config.DEFAULT_TFIDF_DIM)
  let _ = update_search_index(wiki_dir, "kgfs", provider) catch { _ => panic() }
  write_test_file(
    wiki_dir + "/home.md",
    "# Home\n\nIncremental quartzalpha content.\n",
  )
  let page_ids : Map[String, Bool] = {}
  page_ids["home"] = true
  let _ = update_search_index_incremental(wiki_dir, "kgfs", provider, page_ids) catch {
    _ => panic()
  }
  let idx = match @wiki_search.WikiSearchIndex::load(wiki_dir) {
    Some(i) => i
    None => panic()
  }
  let mut saw_home_update = false
  let mut saw_other = false
  for entry in idx.sections {
    if entry.1.page_id == "home" {
      assert_true(entry.1.content.contains("quartzalpha"))
      saw_home_update = true
    }
    if entry.1.page_id == "other" {
      assert_true(entry.1.content.contains("Stable beta"))
      saw_other = true
    }
  }
  assert_true(saw_home_update)
  assert_true(saw_other)
}
