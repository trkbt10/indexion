///|
/// # Wiki Ingest
///
/// Incremental change detection for wiki pages.
/// Detects which source files have changed since the last ingest
/// and generates update tasks for affected wiki pages.

///|
/// Ingest manifest file name (SoT).
pub const INGEST_MANIFEST_FILE : String = "ingest-manifest.json"

///|
/// A single source file change.
pub struct SourceChange {
  file : String
  change_type : String // "modified" | "added" | "deleted"
  old_hash : String
  new_hash : String
} derive(ToJson)

///|
/// A task for updating a wiki page.
pub struct IngestTask {
  page_id : String
  page_title : String
  action : String // "update" | "review"
  reason : String
  changed_sources : Array[SourceChange]
  priority : Int
} derive(ToJson)

///|
/// Per-page source state tracking.
pub struct PageSourceState {
  /// Content hash of the wiki page itself.
  page_hash : String
  /// Map of source file path → content hash.
  source_hashes : Map[String, String]
} derive(ToJson)

///|
impl @json.FromJson for PageSourceState with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError(
      (path, "PageSourceState::from_json: expected object"),
    )
  }
  let page_hash = match obj.get("page_hash") {
    Some(String(s)) => s
    _ => ""
  }
  let source_hashes : Map[String, String] = {}
  match obj.get("source_hashes") {
    Some(Object(d)) =>
      for entry in d {
        match entry.1 {
          String(s) => source_hashes[entry.0] = s
          _ => ()
        }
      }
    _ => ()
  }
  { page_hash, source_hashes }
}

///|
/// The full ingest manifest, persisted between runs.
pub struct IngestManifest {
  version : String
  page_states : Map[String, PageSourceState]
} derive(ToJson)

///|
impl @json.FromJson for IngestManifest with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError(
      (path, "IngestManifest::from_json: expected object"),
    )
  }
  let version = match obj.get("version") {
    Some(String(s)) => s
    _ => "1"
  }
  let page_states : Map[String, PageSourceState] = {}
  match obj.get("page_states") {
    Some(Object(d)) =>
      for entry in d {
        let state : PageSourceState = @json.from_json(entry.1) catch {
          _ => continue
        }
        page_states[entry.0] = state
      }
    _ => ()
  }
  { version, page_states }
}

///|
/// The result of an ingest analysis.
pub struct IngestResult {
  tasks : Array[IngestTask]
  new_manifest : IngestManifest
}

///|
/// Load the ingest manifest from a wiki directory.
pub fn load_manifest(wiki_dir : String) -> IngestManifest {
  let path = wiki_dir + "/" + INGEST_MANIFEST_FILE
  if !@fs.path_exists(path) {
    return { version: "1", page_states: {} }
  }
  let content = @fs.read_file_to_string(path) catch {
    _ => return { version: "1", page_states: {} }
  }
  let json = @json.parse(content) catch {
    _ => return { version: "1", page_states: {} }
  }
  @json.from_json(json) catch {
    _ => { version: "1", page_states: {} }
  }
}

///|
/// Save the ingest manifest to a wiki directory.
pub fn save_manifest(manifest : IngestManifest, wiki_dir : String) -> Unit {
  let path = wiki_dir + "/" + INGEST_MANIFEST_FILE
  @config.ensure_dir_recursive(wiki_dir)
  let content = manifest.to_json().stringify(indent=2)
  @fs.write_string_to_file(path, content) catch {
    _ => ()
  }
}

///|
/// Analyze wiki pages for source changes since the last ingest.
/// Returns tasks for pages that need updating and a new manifest.
pub fn analyze(wiki : @wiki_types.WikiData, wiki_dir : String) -> IngestResult {
  let prev = load_manifest(wiki_dir)
  let tasks : Array[IngestTask] = []
  let new_states : Map[String, PageSourceState] = {}
  // Derive project root from wiki_dir so source paths resolve correctly
  let project_root = match
    @config.find_project_root_from(@config.dirname(wiki_dir)) {
    Some(root) => root
    None => @config.dirname(wiki_dir)
  }
  for entry in wiki.pages {
    let (page_id, page) = (entry.0, entry.1)
    // Compute current page hash
    let page_hash = @cas_hash.compute_hash(page.content).value
    // Compute current source hashes
    let current_hashes : Map[String, String] = {}
    for src in page.sources {
      if src.file.length() > 0 {
        let resolved = @config.resolve_path(project_root, src.file)
        let content = @fs.read_file_to_string(resolved) catch { _ => "" }
        if content.length() > 0 {
          current_hashes[src.file] = @cas_hash.compute_hash(content).value
        }
      }
    }
    // Store new state
    new_states[page_id] = { page_hash, source_hashes: current_hashes }
    // Compare with previous state
    let changes : Array[SourceChange] = []
    match prev.page_states.get(page_id) {
      Some(prev_state) => {
        // Check for modified/deleted sources
        for prev_entry in prev_state.source_hashes {
          let (file, old_hash) = (prev_entry.0, prev_entry.1)
          match current_hashes.get(file) {
            Some(new_hash) =>
              if new_hash != old_hash {
                changes.push({
                  file,
                  change_type: "modified",
                  old_hash,
                  new_hash,
                })
              }
            None =>
              changes.push({
                file,
                change_type: "deleted",
                old_hash,
                new_hash: "",
              })
          }
        }
        // Check for added sources
        for cur_entry in current_hashes {
          let file = cur_entry.0
          if !prev_state.source_hashes.contains(file) {
            changes.push({
              file,
              change_type: "added",
              old_hash: "",
              new_hash: cur_entry.1,
            })
          }
        }
      }
      None =>
        // New page or first run — no changes to report
        ()
    }
    if changes.length() > 0 {
      let mut deleted_count = 0
      let mut modified_count = 0
      for c in changes {
        if c.change_type == "deleted" {
          deleted_count += 1
        } else {
          modified_count += 1
        }
      }
      let reason = modified_count.to_string() +
        " source(s) modified, " +
        deleted_count.to_string() +
        " deleted"
      let priority = if deleted_count > 0 { 1 } else { 2 }
      tasks.push({
        page_id,
        page_title: page.title,
        action: if deleted_count > 0 {
          "review"
        } else {
          "update"
        },
        reason,
        changed_sources: changes,
        priority,
      })
    }
  }
  { tasks, new_manifest: { version: "1", page_states: new_states } }
}

///|
/// Convert ingest tasks to a PlanDocument for rendering.
pub fn tasks_to_plan_document(
  tasks : Array[IngestTask],
) -> @plan_types.PlanDocument {
  let doc = @plan_types.PlanDocument::new("Wiki Ingest Report")
  doc.set_description(
    "Source change analysis for wiki pages. " +
    tasks.length().to_string() +
    " pages need attention.",
  )
  doc.set_meta("labels", "wiki,ingest")
  if tasks.length() == 0 {
    let items : Array[@plan_types.ListItem] = []
    items.push(@plan_types.ListItem::simple("All wiki pages are up to date."))
    doc.add_section(
      @plan_types.PlanSection::new(
        "status",
        "Status",
        @plan_types.SectionContent::list(items),
      ),
    )
    return doc
  }
  // Group by action
  let update_items : Array[@plan_types.ChecklistItem] = []
  let review_items : Array[@plan_types.ChecklistItem] = []
  for task in tasks {
    let label = task.page_title + " — " + task.reason
    let item = @plan_types.ChecklistItem::with_priority(label, task.priority)
    if task.action == "review" {
      review_items.push(item)
    } else {
      update_items.push(item)
    }
  }
  if review_items.length() > 0 {
    doc.add_section(
      @plan_types.PlanSection::new(
        "review",
        "Pages Requiring Review (sources deleted)",
        @plan_types.SectionContent::checklist(review_items),
      ),
    )
  }
  if update_items.length() > 0 {
    doc.add_section(
      @plan_types.PlanSection::new(
        "update",
        "Pages Requiring Update (sources modified)",
        @plan_types.SectionContent::checklist(update_items),
      ),
    )
  }
  doc
}
