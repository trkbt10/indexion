/// Glob-based loader for story document groups.
///
/// Two design points:
///
/// 1. **No folder convention.** The CLI passes glob patterns or paths
///    explicitly. Filenames carry no semantic weight; the only signal
///    is which group a path belongs to.
///
/// 2. **No project-wide ignore rules.** Story commands operate on
///    user-explicit patterns, not on the project source tree. Routing
///    through `@pipeline.discover_files` would force `.gitignore` and
///    `.indexionignore` rules onto the user's input — surprising when
///    the user asks indexion to look at, say, `fixtures/story/...`
///    that the project ignores for code-analysis purposes. We use the
///    glob SoT (`@glob.expand_glob` / `@glob.has_glob_pattern`) and a
///    direct directory walk to honour exactly the patterns the user
///    typed.
///
/// Path normalisation comes from `@config_paths.normalize_path`. File
/// reads go through `@fs.read_file_to_string`.

///|
/// Resolve glob patterns and paths to a list of `StoryDocument` values.
///
/// `patterns` accepts:
///   - A literal file path (loaded directly).
///   - A literal directory path (recursively walked).
///   - A glob pattern (resolved via `@glob.expand_glob`; matched
///     entries are then walked the same way as literal paths).
///
/// Unreadable files are silently skipped so a stray broken symlink
/// does not abort an analysis. Empty files are skipped because they
/// produce no tokens. The output is sorted by normalised path so
/// runs are deterministic.
pub fn load_documents(patterns : Array[String]) -> Array[StoryDocument] {
  if patterns.is_empty() {
    return []
  }
  let collected_paths : Array[String] = []
  for pattern in patterns {
    if @glob.has_glob_pattern(pattern) {
      let expanded = @glob.expand_glob(pattern)
      for ep in expanded {
        walk_path(ep, collected_paths)
      }
    } else {
      walk_path(pattern, collected_paths)
    }
  }
  let result : Array[StoryDocument] = []
  let seen : Map[String, Bool] = {}
  for path in collected_paths {
    let normalized = @config_paths.normalize_path(path)
    if seen.contains(normalized) {
      continue
    }
    seen[normalized] = true
    let content = @fs.read_file_to_string(path) catch {
      _ => continue
    }
    if content.length() == 0 {
      continue
    }
    result.push(StoryDocument::new(normalized, content))
  }
  result.sort_by(fn(a, b) { a.path.compare(b.path) })
  result
}

///|
/// Walk a single filesystem path: if it's a file, append it; if it's a
/// directory, recurse into its entries.
///
/// Path checks go through `@fs.path_exists` / `@fs.is_dir` (SoT) and
/// child paths are joined via `@config_paths.join_path` (SoT).
fn walk_path(path : String, out : Array[String]) -> Unit {
  if !@fs.path_exists(path) {
    return
  }
  let is_dir = @fs.is_dir(path) catch {
    _ => false
  }
  if is_dir {
    let entries = @fs.read_dir(path) catch {
      _ => return
    }
    for entry in entries {
      let child = @config_paths.join_path(path, entry)
      walk_path(child, out)
    }
  } else {
    out.push(path)
  }
}

///|
/// Convenience: load both spec and impl groups in one call.
pub fn load_groups(
  spec_patterns : Array[String],
  impl_patterns : Array[String],
) -> StoryGroups {
  let spec = load_documents(spec_patterns)
  let impl_ = load_documents(impl_patterns)
  StoryGroups::new(spec, impl_)
}
