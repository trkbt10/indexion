///|
/// Shared wiki workspace operations.
///
/// This package is the SoT for locating wiki directories, checking freshness of
/// persisted wiki search indexes, and rebuilding them when needed.

///|
pub struct SearchUpdateResult {
  sections_count : Int
  saved : Bool
}

///|
priv struct WikiUpdatePlan {
  mut full_rebuild : Bool
  page_ids : Map[String, Bool]
}

///|
fn WikiUpdatePlan::new() -> WikiUpdatePlan {
  { full_rebuild: false, page_ids: {} }
}

///|
fn WikiUpdatePlan::is_stale(self : WikiUpdatePlan) -> Bool {
  self.full_rebuild || self.page_ids.length() > 0
}

///|
fn WikiUpdatePlan::add_page(self : WikiUpdatePlan, page_id : String) -> Unit {
  self.page_ids[page_id] = true
}

///|
pub const DEFAULT_WIKI_DIR : String = ".indexion/wiki"

///|
fn is_default_wiki_path(path : String) -> Bool {
  path == DEFAULT_WIKI_DIR ||
  path == DEFAULT_WIKI_DIR + "/" ||
  path.has_suffix("/" + DEFAULT_WIKI_DIR) ||
  path.has_suffix("/" + DEFAULT_WIKI_DIR + "/")
}

///|
fn default_wiki_base(path : String) -> String {
  let total = path.to_array().length()
  let suffix_len = DEFAULT_WIKI_DIR.to_array().length()
  let base_len = if path.has_suffix(DEFAULT_WIKI_DIR + "/") {
    total - suffix_len - 1
  } else {
    total - suffix_len
  }
  let base = @config.substring(path, 0, base_len)
  let trimmed = if base.has_suffix("/") {
    @config.substring(base, 0, base.to_array().length() - 1)
  } else {
    base
  }
  if trimmed.length() == 0 {
    "."
  } else {
    trimmed
  }
}

///|
/// Resolve the default project wiki from a workspace anchor.
pub fn resolve_project_wiki_dir(anchor_dir : String) -> String? {
  @config.resolve_project_indexion_dir(anchor_dir, "wiki")
}

///|
/// Resolve an explicit wiki directory argument.
///
/// The default `.indexion/wiki` form is project-root-relative. Other paths are
/// explicit and are returned as-is after normalization, even if they do not
/// exist yet.
pub fn resolve_wiki_dir(path : String) -> String? {
  let normalized = @config.normalize_path(path)
  if @fs.path_exists(@wiki_types.wiki_manifest_path(normalized)) {
    Some(normalized)
  } else if is_default_wiki_path(normalized) {
    resolve_project_wiki_dir(default_wiki_base(normalized))
  } else {
    Some(normalized)
  }
}

///|
pub fn is_wiki_dir(wiki_dir : String) -> Bool {
  @fs.path_exists(@wiki_types.wiki_manifest_path(wiki_dir))
}

///|
pub fn assets_dir(wiki_dir : String) -> String {
  @config.join_path(wiki_dir, "assets")
}

///|
pub fn is_wiki_search_generated_path(path : String) -> Bool {
  path.has_suffix("/" + @wiki_search.VECTORS_FILE) ||
  path.has_suffix("/" + @wiki_search.SECTIONS_FILE) ||
  path.has_suffix("/" + @wiki_search.VOCABULARY_FILE) ||
  path.has_suffix("/" + @wiki_types.WIKI_INDEX_FILE)
}

///|
fn load_manifest(wiki_dir : String) -> @wiki_types.WikiManifest? {
  let text = @fs.read_file_to_string(@wiki_types.wiki_manifest_path(wiki_dir)) catch {
    _ => return None
  }
  let json : Json = @json.parse(text) catch { _ => return None }
  let manifest : @wiki_types.WikiManifest = @json.from_json(json) catch {
    _ => return None
  }
  Some(manifest)
}

///|
pub fn wiki_content_paths(wiki_dir : String) -> Array[String]? {
  let manifest = match load_manifest(wiki_dir) {
    Some(m) => m
    None => return None
  }
  let paths : Array[String] = [@wiki_types.wiki_manifest_path(wiki_dir)]
  for page in manifest.pages {
    if page.file.length() > 0 {
      paths.push(@config.join_path(wiki_dir, page.file))
    }
  }
  Some(paths)
}

///|
fn page_id_for_path(
  wiki_dir : String,
  manifest : @wiki_types.WikiManifest,
  path : String,
) -> String? {
  let normalized = @config.normalize_path(path)
  if normalized ==
    @config.normalize_path(@wiki_types.wiki_manifest_path(wiki_dir)) {
    return None
  }
  for page in manifest.pages {
    if @config.normalize_path(@config.join_path(wiki_dir, page.file)) ==
      normalized {
      return Some(page.id)
    }
  }
  None
}

///|
fn mark_content_path_changed(
  plan : WikiUpdatePlan,
  wiki_dir : String,
  manifest : @wiki_types.WikiManifest,
  path : String,
) -> Unit {
  if @config.normalize_path(path) ==
    @config.normalize_path(@wiki_types.wiki_manifest_path(wiki_dir)) {
    plan.full_rebuild = true
    return
  }
  match page_id_for_path(wiki_dir, manifest, path) {
    Some(page_id) => plan.add_page(page_id)
    None => plan.full_rebuild = true
  }
}

///|
async fn mark_mtime_changes(
  plan : WikiUpdatePlan,
  wiki_dir : String,
  manifest : @wiki_types.WikiManifest,
  paths : Array[String],
  timestamp : Int,
) -> Unit {
  for path in paths {
    match @git.file_mtime_seconds(path) {
      Some(seconds) =>
        if seconds > timestamp {
          mark_content_path_changed(plan, wiki_dir, manifest, path)
        }
      None => plan.full_rebuild = true
    }
  }
}

///|
async fn mark_worktree_changes(
  plan : WikiUpdatePlan,
  repo_root : String,
  wiki_dir : String,
  manifest : @wiki_types.WikiManifest,
  paths : Array[String],
  timestamp : Int,
) -> Unit {
  for path in paths {
    if is_wiki_search_generated_path(path) {
      continue
    }
    let full_path = @config.join_path(repo_root, path)
    match @git.file_mtime_seconds(full_path) {
      Some(seconds) =>
        if seconds > timestamp {
          mark_content_path_changed(plan, wiki_dir, manifest, full_path)
        }
      None => mark_content_path_changed(plan, wiki_dir, manifest, full_path)
    }
  }
}

///|
async fn mark_committed_content_changes(
  plan : WikiUpdatePlan,
  repo_root : String,
  wiki_dir : String,
  manifest : @wiki_types.WikiManifest,
  paths : Array[String],
  timestamp : Int,
) -> Unit {
  for path in paths {
    match @git.last_commit_seconds(repo_root, path) {
      Some(seconds) =>
        if seconds > timestamp {
          mark_content_path_changed(plan, wiki_dir, manifest, path)
        }
      None => ()
    }
  }
}

///|
async fn update_plan(wiki_dir : String) -> WikiUpdatePlan {
  let plan = WikiUpdatePlan::new()
  if !@wiki_search.exists(wiki_dir) {
    return { full_rebuild: true, page_ids: {} }
  }
  let index_mtime = match
    @git.file_mtime_seconds(
      @config.join_path(wiki_dir, @wiki_search.SECTIONS_FILE),
    ) {
    Some(t) => t
    None => return { full_rebuild: true, page_ids: {} }
  }
  let manifest = match load_manifest(wiki_dir) {
    Some(m) => m
    None => return { full_rebuild: true, page_ids: {} }
  }
  let content_paths = match wiki_content_paths(wiki_dir) {
    Some(paths) => paths
    None => return { full_rebuild: true, page_ids: {} }
  }
  mark_mtime_changes(plan, wiki_dir, manifest, content_paths, index_mtime)
  match @git.repo_root(wiki_dir) {
    Some(repo_root) => {
      match @git.worktree_changed_files(repo_root, [wiki_dir]) {
        Some(files) =>
          mark_worktree_changes(
            plan, repo_root, wiki_dir, manifest, files, index_mtime,
          )
        None => plan.full_rebuild = true
      }
      mark_committed_content_changes(
        plan, repo_root, wiki_dir, manifest, content_paths, index_mtime,
      )
    }
    None => ()
  }
  plan
}

///|
pub async fn may_be_stale(wiki_dir : String) -> Bool {
  update_plan(wiki_dir).is_stale()
}

///|
pub async fn update_search_index(
  wiki_dir : String,
  specs_dir : String,
  provider : @embed_config.EmbeddingProvider,
) -> SearchUpdateResult? raise @embed.EmbedError {
  let registry = @kgf_features.load_registry(specs_dir~, target_dir=wiki_dir)
  let wiki = match @wiki_reader.load_wiki(wiki_dir, registry~) {
    Some(w) => w
    None => return None
  }
  let index = @wiki_search.build_search_index(wiki.pages, provider, registry~)
  index.save(wiki_dir)
  Some({ sections_count: index.sections.length(), saved: true })
}

///|
async fn update_search_index_incremental(
  wiki_dir : String,
  specs_dir : String,
  provider : @embed_config.EmbeddingProvider,
  page_ids : Map[String, Bool],
) -> SearchUpdateResult? raise @embed.EmbedError {
  let index = match @wiki_search.WikiSearchIndex::load(wiki_dir) {
    Some(idx) => idx
    None => return update_search_index(wiki_dir, specs_dir, provider)
  }
  let registry = @kgf_features.load_registry(specs_dir~, target_dir=wiki_dir)
  let wiki = match @wiki_reader.load_wiki(wiki_dir, registry~) {
    Some(w) => w
    None => return None
  }
  for entry in page_ids {
    let page_id = entry.0
    match wiki.pages.get(page_id) {
      Some(page) =>
        index.update_page(
          page.id,
          page.title,
          page.content,
          path=@config.join_path(wiki_dir, page.file),
          registry~,
        )
      None => return update_search_index(wiki_dir, specs_dir, provider)
    }
  }
  index.save(wiki_dir)
  Some({ sections_count: index.sections.length(), saved: true })
}

///|
pub async fn update_search_index_if_stale(
  wiki_dir : String,
  specs_dir : String,
  provider : @embed_config.EmbeddingProvider,
) -> SearchUpdateResult? {
  let plan = update_plan(wiki_dir)
  if !plan.is_stale() {
    return None
  }
  if plan.full_rebuild {
    return update_search_index(wiki_dir, specs_dir, provider) catch {
      _ => None
    }
  }
  update_search_index_incremental(wiki_dir, specs_dir, provider, plan.page_ids) catch {
    _ => None
  }
}
