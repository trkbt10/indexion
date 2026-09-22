///|
/// Path resolution for indexion configuration.
/// This is the Single Source of Truth for finding kgfs directory.

///|
/// Normalize a project path for config/path resolution.
pub fn normalize_path(path : String) -> String {
  @osenv_path.normalize(path)
}

///|
/// Join base and child as a normalized path.
pub fn join_path(base : String, child : String) -> String {
  if base.length() == 0 {
    normalize_path(child)
  } else if child.length() == 0 {
    normalize_path(base)
  } else {
    @osenv_path.join([base, child]) catch {
      _ => normalize_path(base + "/" + child)
    }
  }
}

///|
/// Directory name for a normalized path.
pub fn dirname(path : String) -> String {
  @osenv_path.dirname(path)
}

///|
/// Basename for a normalized path.
pub fn basename(path : String) -> String {
  @osenv_path.basename(path)
}

///|
/// File extension including the leading dot.
pub fn extension(path : String) -> String {
  @osenv_path.extname(path)
}

///|
/// Extract substring from start (inclusive) to end (exclusive).
/// Clamps both bounds to valid range.
pub fn substring(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let actual_end = if end > chars.length() { chars.length() } else { end }
  let actual_start = if start < 0 { 0 } else { start }
  if actual_start >= actual_end {
    return ""
  }
  let result = StringBuilder()
  for i = actual_start; i < actual_end; i = i + 1 {
    result.write_char(chars[i])
  }
  result.to_string()
}

///|
/// Extract substring from start (inclusive) to end of string.
pub fn substring_from(s : String, start : Int) -> String {
  substring(s, start, s.to_array().length())
}

///|
/// Return whether a path is absolute.
pub fn is_absolute_path(path : String) -> Bool {
  @osenv_path.is_absolute(path)
}

///|
/// Resolve a path against a base directory.
pub fn resolve_path(base_dir : String, path : String) -> String {
  if path.length() == 0 {
    ""
  } else if is_absolute_path(path) {
    normalize_path(path)
  } else {
    join_path(base_dir, path)
  }
}

///|
/// Make `path` relative to `root` when it is inside that root.
pub fn relative_to(root : String, path : String) -> String {
  let normalized_root = normalize_path(root)
  let normalized_path = normalize_path(path)
  if normalized_root == "." {
    normalized_path
  } else {
    @osenv_path.to_relative(normalized_path, normalized_root)
  }
}

///|
/// Find `.indexion.toml` or `.indexion.json` by walking up from target directory.
/// Uses find_project_root to locate the nearest ancestor containing a config file.
pub fn find_indexion_config_path(
  target_dir : String,
  explicit_path? : String = "",
) -> String {
  if explicit_path.length() > 0 {
    return resolve_path(target_dir, explicit_path)
  }
  match find_project_root(target_dir, [".indexion.toml", ".indexion.json"]) {
    Some(root) => {
      let toml_path = join_path(root, ".indexion.toml")
      if is_valid_file(toml_path) {
        return toml_path
      }
      let json_path = join_path(root, ".indexion.json")
      if is_valid_file(json_path) {
        return json_path
      }
      ""
    }
    None => ""
  }
}

///|
/// Base directory for config-relative paths.
pub fn config_base_dir(target_dir : String, config_path : String) -> String {
  if config_path.length() > 0 {
    dirname(config_path)
  } else {
    normalize_path(target_dir)
  }
}

///|
/// Resolve a path value using config directory when present, otherwise target root.
pub fn resolve_config_path_value(
  target_dir : String,
  config_path : String,
  value : String,
) -> String {
  resolve_path(config_base_dir(target_dir, config_path), value)
}

///|
/// Default tool working directory under the target root.
pub fn default_tool_dir(target_dir : String, tool_subdir : String) -> String {
  join_path(normalize_path(target_dir), tool_subdir)
}

///|
let project_root_markers : Array[String] = [
  ".git", ".indexion", ".indexion.toml", ".indexion.json",
]

///|
/// Find the project root by walking up from start_dir, using the standard markers.
/// Returns None if no marker is found.
pub fn find_project_root_from(start_dir : String) -> String? {
  find_project_root(start_dir, project_root_markers)
}

///|
/// Resolve the .indexion tool directory under the project root.
/// Walks up from target_dir to find a project root marker (.git, .indexion, etc.),
/// then returns project_root/.indexion/{tool_subdir}.
/// Returns None if no project root is found.
pub fn resolve_project_indexion_dir(
  target_dir : String,
  tool_subdir : String,
) -> String? {
  match find_project_root_from(target_dir) {
    Some(root) => Some(join_path(root, ".indexion/" + tool_subdir))
    None => None
  }
}

///|
/// Default cache/index directory for `indexion plan reconcile`.
pub fn default_reconcile_index_dir(target_dir : String) -> String? {
  resolve_project_indexion_dir(target_dir, "cache/reconcile")
}

///|
/// Ensure the parent directory of `path` exists.
pub fn ensure_parent_dir(path : String) -> Unit {
  let dir = dirname(path)
  if dir != "." && dir != path {
    ensure_dir_recursive(dir)
  }
}

///|
/// Ensure a directory exists recursively.
pub fn ensure_dir_recursive(path : String) -> Unit {
  let normalized = normalize_path(path)
  if normalized.length() == 0 ||
    normalized == "." ||
    @fs.path_exists(normalized) {
    return
  }
  let parent = dirname(normalized)
  if parent != normalized {
    ensure_dir_recursive(parent)
  }
  @fs.create_dir(normalized) catch {
    _ => ()
  }
}

///|
/// Find a project root by walking up from start_dir to the filesystem root,
/// stopping at a directory that contains any of the given markers (as dir or file).
/// Used for ignore file hoisting boundaries (.git, .indexion, etc.).
pub fn find_project_root(
  start_dir : String,
  markers : Array[String],
) -> String? {
  let mut current = normalize_path(start_dir)
  while true {
    for marker in markers {
      if @fs.path_exists(join_path(current, marker)) {
        return Some(current)
      }
    }
    let parent = dirname(current)
    if parent == current {
      break
    }
    current = parent
  }
  None
}

///|
/// Collect ancestor directories from root down to target_dir (inclusive),
/// ordered top-down. Used for hoisting ignore files from root to target.
pub fn ancestors_top_down(target_dir : String, root : String) -> Array[String] {
  let bottom_up : Array[String] = []
  let mut current = normalize_path(target_dir)
  let normalized_root = normalize_path(root)
  while true {
    bottom_up.push(current)
    if current == normalized_root {
      break
    }
    let parent = dirname(current)
    if parent == current {
      break
    }
    current = parent
  }
  let top_down : Array[String] = []
  for i = bottom_up.length() - 1; i >= 0; i = i - 1 {
    top_down.push(bottom_up[i])
  }
  top_down
}

///|
/// Find the nearest directory containing any configured project marker pattern.
/// Marker patterns are supplied by a caller-owned SoT, such as the KGF registry.
pub fn find_nearest_marker_dir(
  root_dir : String,
  path : String,
  markers : Array[String],
) -> String? {
  if markers.length() == 0 {
    return None
  }
  let normalized_root = normalize_path(root_dir)
  let mut current = normalize_path(path)
  while !is_valid_dir(current) {
    if current == normalized_root || current == "." {
      return None
    }
    let parent = dirname(current)
    if parent == current {
      return None
    }
    current = parent
  }
  while true {
    if has_matching_marker(current, markers) {
      return Some(current)
    }
    if current == normalized_root || current == "." {
      break
    }
    let parent = dirname(current)
    if parent == current {
      break
    }
    current = parent
  }
  None
}

///|
fn has_matching_marker(dir : String, markers : Array[String]) -> Bool {
  let entries = @fs.read_dir(dir) catch { _ => return false }
  for marker in markers {
    for entry in entries {
      if wildcard_match(marker, entry) {
        return true
      }
    }
  }
  false
}

///|
fn wildcard_match(pattern : String, text : String) -> Bool {
  if pattern == "*" {
    return true
  }
  if !pattern.contains("*") {
    return pattern == text
  }
  let parts = split_wildcard_parts(pattern)
  if parts.length() == 0 {
    return true
  }
  let anchored_start = !pattern.has_prefix("*")
  let anchored_end = !pattern.has_suffix("*")
  let mut search_start = 0
  let mut last_match_end = 0
  for i = 0; i < parts.length(); i = i + 1 {
    let part = parts[i]
    let found = find_substring_from(text, part, search_start)
    if found < 0 {
      return false
    }
    if i == 0 && anchored_start && found != 0 {
      return false
    }
    search_start = found + part.length()
    last_match_end = search_start
  }
  if anchored_end {
    last_match_end == text.length()
  } else {
    true
  }
}

///|
fn split_wildcard_parts(pattern : String) -> Array[String] {
  let parts : Array[String] = []
  let current : Array[Char] = []
  for ch in pattern.to_array() {
    if ch == '*' {
      if current.length() > 0 {
        parts.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(ch)
    }
  }
  if current.length() > 0 {
    parts.push(String::from_array(current))
  }
  parts
}

///|
fn find_substring_from(text : String, needle : String, start : Int) -> Int {
  if needle.length() == 0 {
    return start
  }
  if start < 0 || start >= text.length() {
    return -1
  }
  let text_chars = text.to_array()
  let needle_chars = needle.to_array()
  if needle_chars.length() > text_chars.length() {
    return -1
  }
  let max_start = text_chars.length() - needle_chars.length()
  for i = start; i <= max_start; i = i + 1 {
    let mut matched = true
    for j = 0; j < needle_chars.length(); j = j + 1 {
      if text_chars[i + j] != needle_chars[j] {
        matched = false
        break
      }
    }
    if matched {
      return i
    }
  }
  -1
}

///|
fn find_explicit_kgfs_candidate(
  base_dir : String,
  explicit_path : String,
) -> String? {
  if is_valid_dir(explicit_path) {
    return Some(normalize_path(explicit_path))
  }
  let resolved = resolve_path(resolve_to_existing_dir(base_dir), explicit_path)
  if is_valid_dir(resolved) {
    Some(resolved)
  } else {
    None
  }
}

///|
/// Find kgfs directory.
/// Priority:
/// 1. Explicit path (--kgfs-dir CLI option)
/// 2. INDEXION_KGFS_DIR environment variable
/// 3. Global config [global].kgfs_dir
/// 4. kgfs/ relative to target dir (project-local)
/// 5. kgfs/ relative to CWD (development - submodule)
/// 6. OS-standard data directory (get_global_data_dir()/kgfs) - only if non-empty
pub fn find_kgfs_dir(
  explicit_path? : String = "",
  target_dir? : String = ".",
  target_dirs? : Array[String] = [],
) -> String? {
  let search_dirs = normalize_kgfs_target_dirs(target_dir, target_dirs)
  let base_dir = if search_dirs.length() > 0 { search_dirs[0] } else { "." }
  if explicit_path.length() > 0 {
    return find_explicit_kgfs_candidate(base_dir, explicit_path)
  }
  let env_candidate = match @env.get_env_var("INDEXION_KGFS_DIR") {
    Some(dir) =>
      if dir.length() > 0 && is_valid_dir(dir) {
        Some(normalize_path(dir))
      } else {
        None
      }
    None => None
  }
  let global_candidate = match load_global_config().kgfs_dir {
    Some(dir) => if is_valid_dir(dir) { Some(dir) } else { None }
    None => None
  }
  let project_candidate = find_project_kgfs_candidate(search_dirs)
  let cwd_candidate = if is_valid_dir("kgfs") {
    Some(normalize_path("kgfs"))
  } else {
    None
  }
  let data_candidate = match get_global_data_dir() {
    Some(data_dir) => {
      let kgfs_path = join_path(data_dir, "kgfs")
      if is_valid_dir(kgfs_path) && !is_empty_dir(kgfs_path) {
        Some(kgfs_path)
      } else {
        None
      }
    }
    None => None
  }
  select_kgfs_dir_candidate(
    None,
    env_candidate,
    global_candidate,
    project_candidate,
    cwd_candidate,
    data_candidate,
  )
}

///|
/// Subdirectory name under `.indexion/` holding project-local KGF specs.
/// Mirrors the layout of the installed spec set, so a project can place
/// `.indexion/kgfs/programming/rust.kgf` — or just `.indexion/kgfs/rust.kgf` —
/// to replace one installed spec without copying the rest.
pub const KGFS_OVERLAY_SUBDIR : String = "kgfs"

///|
/// Relative path of the project-local KGF overlay directory from the project
/// root. Used in user-facing messages and documentation.
pub fn kgfs_overlay_relative() -> String {
  ".indexion/" + KGFS_OVERLAY_SUBDIR
}

///|
/// Find the project-local KGF spec overlay directory for the analysed target.
///
/// Walks up from each target directory to the nearest project root (the same
/// markers `find_project_root_from` uses) and returns `<root>/.indexion/kgfs`
/// when it exists. Targets that resolve to the same overlay contribute it once.
pub fn find_kgfs_overlay_dirs(
  target_dir? : String = ".",
  target_dirs? : Array[String] = [],
) -> Array[String] {
  let search_dirs = normalize_kgfs_target_dirs(target_dir, target_dirs)
  let overlays : Array[String] = []
  for dir in search_dirs {
    let start = resolve_to_existing_dir(dir)
    match resolve_project_indexion_dir(start, KGFS_OVERLAY_SUBDIR) {
      Some(candidate) => {
        let normalized = normalize_path(candidate)
        if is_valid_dir(normalized) && !contains_path(overlays, normalized) {
          overlays.push(normalized)
        }
      }
      None => ()
    }
  }
  overlays
}

///|
/// Resolve the full, ordered list of KGF spec directories to load.
///
/// This is the SoT for spec-set composition. The result is layered: index 0 is
/// the base set resolved exactly as `find_kgfs_dir` does today, and every
/// following entry is an overlay applied on top of it, so a spec found later
/// replaces an earlier one of the same language name.
///
/// Layering rules:
/// - `explicit_paths` (repeated `--specs-dir`) replaces the whole chain: the
///   first entry is the base, the rest are overlays, and no implicit overlay
///   is added. Giving the option once therefore behaves exactly as before.
/// - Otherwise the base comes from `find_kgfs_dir`, and the analysed project's
///   `.indexion/kgfs/` is layered on top when present.
/// - A directory already in the chain is never added twice. This matters for
///   this repository, whose own `kgfs/` submodule *is* the base set: resolving
///   it as base and then again as an overlay would load it twice.
///
/// Returns an empty array when no base set can be found and no overlay exists.
pub fn resolve_kgfs_dirs(
  explicit_paths? : Array[String] = [],
  explicit_path? : String = "",
  target_dir? : String = ".",
  target_dirs? : Array[String] = [],
) -> Array[String] {
  let requested = collect_explicit_kgfs_paths(explicit_paths, explicit_path)
  let dirs : Array[String] = []
  if requested.length() > 0 {
    let search_dirs = normalize_kgfs_target_dirs(target_dir, target_dirs)
    let base_dir = if search_dirs.length() > 0 { search_dirs[0] } else { "." }
    for path in requested {
      match find_explicit_kgfs_candidate(base_dir, path) {
        Some(resolved) => push_unique_path(dirs, resolved)
        None => ()
      }
    }
    return dirs
  }
  match find_kgfs_dir(target_dir~, target_dirs~) {
    Some(base) => push_unique_path(dirs, base)
    None => ()
  }
  for overlay in find_kgfs_overlay_dirs(target_dir~, target_dirs~) {
    push_unique_path(dirs, overlay)
  }
  dirs
}

///|
/// Merge the repeated `--specs-dir` values with the single-value form used by
/// callers that have not been migrated, dropping empty entries.
fn collect_explicit_kgfs_paths(
  explicit_paths : Array[String],
  explicit_path : String,
) -> Array[String] {
  let requested : Array[String] = []
  for path in explicit_paths {
    if path.length() > 0 {
      push_unique_path(requested, path)
    }
  }
  if explicit_path.length() > 0 {
    push_unique_path(requested, explicit_path)
  }
  requested
}

///|
fn contains_path(paths : Array[String], path : String) -> Bool {
  for existing in paths {
    if existing == path {
      return true
    }
  }
  false
}

///|
fn push_unique_path(paths : Array[String], path : String) -> Unit {
  if !contains_path(paths, path) {
    paths.push(path)
  }
}

///|
/// Resolve the directory containing KGF transpile specs (`<src>-to-<tgt>.json`).
///
/// Transpile specs are mappings between two KGFs and live at
/// `kgf-transpile/` at the project root. They are intentionally *not*
/// under `kgfs/` because they are not KGF specs themselves. This is the
/// SoT for transpile-spec directory resolution; do not hardcode the
/// `kgf-transpile` literal in callers — go through this function so the
/// project layout can be changed in one place.
///
/// Resolution mirrors `find_kgfs_dir`: explicit override → env var
/// `INDEXION_KGF_TRANSPILE_DIR` → project-root-relative `kgf-transpile/`.
pub fn find_kgf_transpile_dir(
  explicit_path? : String = "",
  target_dir? : String = ".",
) -> String? {
  let base_dir = if target_dir.length() > 0 { target_dir } else { "." }
  if explicit_path.length() > 0 {
    let resolved = resolve_path(base_dir, explicit_path)
    if is_valid_dir(resolved) {
      return Some(resolved)
    }
  }
  match @env.get_env_var("INDEXION_KGF_TRANSPILE_DIR") {
    Some(dir) =>
      if dir.length() > 0 && is_valid_dir(dir) {
        return Some(normalize_path(dir))
      }
    None => ()
  }
  // Walk up from base_dir looking for a `kgf-transpile` sibling.
  match find_nearest_marker_dir(base_dir, base_dir, ["kgf-transpile"]) {
    Some(parent) => {
      let candidate = join_path(parent, "kgf-transpile")
      if is_valid_dir(candidate) {
        return Some(normalize_path(candidate))
      }
    }
    None => ()
  }
  None
}

///|
/// Get the kgfs installation directory (SoT for write path).
/// Returns the OS-standard data directory with kgfs subdirectory.
/// Used by `kgf install`, `update`, and `init --global`.
pub fn get_kgfs_install_dir() -> String? {
  match get_global_data_dir() {
    Some(data_dir) => Some(join_path(data_dir, "kgfs"))
    None =>
      match get_install_dir() {
        Some(dir) => Some(join_path(dir, "kgfs"))
        None => None
      }
  }
}

///|
/// Get the wiki frontend installation directory.
/// Returns the OS-standard data directory with wiki subdirectory.
pub fn get_wiki_install_dir() -> String? {
  match get_global_data_dir() {
    Some(data_dir) => Some(join_path(data_dir, "wiki"))
    None =>
      match get_install_dir() {
        Some(dir) => Some(join_path(dir, "wiki"))
        None => None
      }
  }
}

///|
fn normalize_kgfs_target_dirs(
  target_dir : String,
  target_dirs : Array[String],
) -> Array[String] {
  let normalized : Array[String] = []
  if target_dirs.length() > 0 {
    for dir in target_dirs {
      normalized.push(normalize_path(dir))
    }
  } else {
    normalized.push(normalize_path(target_dir))
  }
  normalized
}

///|
/// Walks from each target dir upward, returning the first ancestor that
/// contains a `kgfs/` directory. This supports invocations where the CLI is
/// run from a subdirectory or where the target path is a deeply-nested file —
/// the project root is discovered rather than required to be CWD.
fn find_project_kgfs_candidate(target_dirs : Array[String]) -> String? {
  for dir in target_dirs {
    let start = resolve_to_existing_dir(dir)
    let mut current = start
    while current.length() > 0 {
      let candidate = join_path(current, "kgfs")
      if is_valid_dir(candidate) {
        return Some(candidate)
      }
      let parent = dirname(current)
      if parent == current || parent.length() == 0 {
        break
      }
      current = parent
    }
  }
  None
}

///|
/// For a target path that may be a file (e.g. `src/foo.mbt`), climb to the
/// nearest existing directory so the ancestor walk starts from a real dir.
fn resolve_to_existing_dir(path : String) -> String {
  let normalized = normalize_path(path)
  if is_valid_dir(normalized) {
    return normalized
  }
  if is_valid_file(normalized) {
    return dirname(normalized)
  }
  // Path doesn't exist on disk (e.g. a glob-style include). Fall back to the
  // literal normalized form so the ancestor walk can still try its parents.
  normalized
}

///|
/// Check if a directory is empty (contains no files or subdirectories).
fn is_empty_dir(path : String) -> Bool {
  let entries = @fs.read_dir(path) catch { _ => return true }
  entries.length() == 0
}

///|
fn select_kgfs_dir_candidate(
  explicit_candidate : String?,
  env_candidate : String?,
  global_candidate : String?,
  project_candidate : String?,
  cwd_candidate : String?,
  data_candidate : String?,
) -> String? {
  match explicit_candidate {
    Some(_) => explicit_candidate
    None =>
      match env_candidate {
        Some(_) => env_candidate
        None =>
          match global_candidate {
            Some(_) => global_candidate
            None =>
              match project_candidate {
                Some(_) => project_candidate
                None =>
                  match cwd_candidate {
                    Some(_) => cwd_candidate
                    None => data_candidate
                  }
              }
          }
      }
  }
}

///|
/// Check if a path is a valid directory.
fn is_valid_dir(path : String) -> Bool {
  @fs.is_dir(path) catch {
    _ => false
  }
}

///|
/// Check if a path is a valid file.
fn is_valid_file(path : String) -> Bool {
  @fs.is_file(path) catch {
    _ => false
  }
}

///|
pub fn find_last_char(text : String, target : Char) -> Int {
  let chars = text.to_array()
  let mut idx = -1
  for i, ch in chars {
    if ch == target {
      idx = i
    }
  }
  idx
}
