// Wbtests for the story wiki planner.
//
// These cover the planner's responsibility — turning a `StoryGroups`'
// spec side into a list of `PageProposal` values — without touching the
// filesystem.

///|
fn make_doc(path : String, content : String) -> @story.StoryDocument {
  @story.StoryDocument::new(path, content)
}

///|
fn ids_from(plan : StoryWikiPlan) -> Array[String] {
  let result : Array[String] = []
  for p in plan.proposals {
    result.push(p.id)
  }
  result
}

///|
fn contains(arr : Array[String], value : String) -> Bool {
  for a in arr {
    if a == value {
      return true
    }
  }
  false
}

///|
test "planner: each heading section becomes a page" {
  let groups = @story.StoryGroups::new(
    [
      make_doc(
        "spec/cast.md",
        (
          #|## Alice
          #|
          #|A protagonist.
          #|
          #|## Bob
          #|
          #|A foil.
          #|
          #|## Carol
          #|
          #|A confidant.
        ),
      ),
    ],
    [],
  )
  let plan = plan_story_wiki(groups)
  assert_eq(plan.proposals.length(), 3)
  let ids = ids_from(plan)
  assert_true(contains(ids, "cast-alice"))
  assert_true(contains(ids, "cast-bob"))
  assert_true(contains(ids, "cast-carol"))
}

///|
test "planner: pages from different docs use the doc stem to disambiguate" {
  let groups = @story.StoryGroups::new(
    [
      make_doc("spec/draft1.md", "## Garden\n\nA walled garden."),
      make_doc("spec/draft2.md", "## Garden\n\nThe revised garden."),
    ],
    [],
  )
  let plan = plan_story_wiki(groups)
  assert_eq(plan.proposals.length(), 2)
  let ids = ids_from(plan)
  assert_true(contains(ids, "draft1-garden"))
  assert_true(contains(ids, "draft2-garden"))
}

///|
test "planner: CJK headings produce non-empty slugs" {
  let groups = @story.StoryGroups::new(
    [
      make_doc(
        "spec/characters.md",
        (
          #|## 宋金花
          #|
          #|主人公。
          #|
          #|## 外国人の客
          #|
          #|誤認される男。
        ),
      ),
    ],
    [],
  )
  let plan = plan_story_wiki(groups)
  assert_eq(plan.proposals.length(), 2)
  let ids = ids_from(plan)
  for id in ids {
    assert_true(id.has_prefix("characters-"))
    assert_true(id.length() > "characters-".length())
  }
}

///|
test "planner: heading-less doc becomes a single page named after stem" {
  let groups = @story.StoryGroups::new(
    [
      make_doc(
        "spec/freeform.md", "Alice and Bob, side by side, with no headings.",
      ),
    ],
    [],
  )
  let plan = plan_story_wiki(groups)
  assert_eq(plan.proposals.length(), 1)
  let p = plan.proposals[0]
  assert_eq(p.title, "freeform")
  assert_eq(p.id, "freeform-freeform")
}

///|
test "planner: empty groups produce no pages" {
  let groups = @story.StoryGroups::new([], [])
  let plan = plan_story_wiki(groups)
  assert_eq(plan.proposals.length(), 0)
  assert_eq(plan.source_doc_count, 0)
}

///|
fn temp_story_wiki_dir(label : String) -> String {
  let dir = "/tmp/indexion-story-wiki/" + label + "-" + @env.now().to_string()
  @config_paths.ensure_dir_recursive(dir)
  dir
}

///|
async test "builder: initial build creates wiki search index artifacts" {
  let _unit = @async.with_task_group(_group => ())
  let wiki_dir = temp_story_wiki_dir("initial-index")
  let groups = @story.StoryGroups::new(
    [
      make_doc(
        "spec/cast.md",
        (
          #|## Alice
          #|
          #|Alice is a protagonist connected to the archive garden.
        ),
      ),
    ],
    [],
  )
  let plan = plan_story_wiki(groups)
  let result = match build_story_wiki(plan, wiki_dir, "test") {
    Some(r) => r
    None => panic()
  }
  assert_eq(result.written.length(), 1)
  assert_true(@fs.path_exists(wiki_dir + "/" + @wiki_search.VECTORS_FILE))
  assert_true(@fs.path_exists(wiki_dir + "/" + @wiki_search.SECTIONS_FILE))
  assert_true(@fs.path_exists(wiki_dir + "/" + @wiki_search.VOCABULARY_FILE))
  let idx = match @wiki_search.WikiSearchIndex::load(wiki_dir) {
    Some(i) => i
    None => panic()
  }
  assert_true(idx.sections.length() > 0)
  let mut saw_content = false
  for entry in idx.sections {
    if entry.1.content.contains("archive garden") {
      saw_content = true
    }
  }
  assert_true(saw_content)
}
