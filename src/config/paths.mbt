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
    try {
      @osenv_path.join([base, child])
    } catch {
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
/// Find `.indexion.toml` or `.indexion.json` for a target directory.
pub fn find_indexion_config_path(
  target_dir : String,
  explicit_path? : String = "",
) -> String {
  if explicit_path.length() > 0 {
    return resolve_path(target_dir, explicit_path)
  }
  let root = normalize_path(target_dir)
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
/// Default cache/index directory for `indexion plan reconcile`.
pub fn default_reconcile_index_dir(target_dir : String) -> String {
  default_tool_dir(target_dir, ".indexion/cache/reconcile")
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
  if not(is_valid_dir(current)) {
    current = dirname(current)
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
  if not(pattern.contains("*")) {
    return pattern == text
  }
  let parts = split_wildcard_parts(pattern)
  if parts.length() == 0 {
    return true
  }
  let anchored_start = not(pattern.has_prefix("*"))
  let anchored_end = not(pattern.has_suffix("*"))
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
  let explicit_candidate = if explicit_path.length() > 0 {
    let resolved = resolve_path(base_dir, explicit_path)
    if is_valid_dir(resolved) {
      Some(resolved)
    } else {
      None
    }
  } else {
    None
  }
  let env_candidate = match @sys.get_env_var("INDEXION_KGFS_DIR") {
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
      if is_valid_dir(kgfs_path) && not(is_empty_dir(kgfs_path)) {
        Some(kgfs_path)
      } else {
        None
      }
    }
    None => None
  }
  select_kgfs_dir_candidate(
    explicit_candidate, env_candidate, global_candidate, project_candidate, cwd_candidate,
    data_candidate,
  )
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
fn find_project_kgfs_candidate(target_dirs : Array[String]) -> String? {
  for dir in target_dirs {
    let project_kgfs = join_path(dir, "kgfs")
    if is_valid_dir(project_kgfs) {
      return Some(project_kgfs)
    }
  }
  None
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
fn find_last_char(text : String, target : Char) -> Int {
  let chars = text.to_array()
  let mut idx = -1
  for i, ch in chars {
    if ch == target {
      idx = i
    }
  }
  idx
}
