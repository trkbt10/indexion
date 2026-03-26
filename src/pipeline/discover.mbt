///|
/// File discovery utilities for pipeline.
/// Consolidates file collection logic from graph and readme CLIs.

///|
/// Options for file discovery.
pub struct DiscoverOptions {
  recursive : Bool
  includes : Array[String]
  excludes : Array[String]
  /// KGF ignore patterns: (pattern, language)
  kgf_ignore : Array[(String, String)]
  /// Root directory for loading project-level ignore files (.gitignore, .indexionignore)
  root_dir : String
}

///|
/// Create default discover options.
pub fn DiscoverOptions::default() -> DiscoverOptions {
  { recursive: true, includes: [], excludes: [], kgf_ignore: [], root_dir: "" }
}

///|
/// Create discover options.
pub fn DiscoverOptions::new(
  recursive? : Bool = true,
  includes? : Array[String] = [],
  excludes? : Array[String] = [],
  kgf_ignore? : Array[(String, String)] = [],
  root_dir? : String = "",
) -> DiscoverOptions {
  { recursive, includes, excludes, kgf_ignore, root_dir }
}

///|
/// Collect all file paths from given input paths.
/// Supports glob patterns (e.g., "src/**/*.mbt").
/// Respects includes, excludes, and recursion settings.
/// Loads project-level ignore files from root_dir if specified.
pub fn discover_files(
  paths : Array[String],
  options : DiscoverOptions,
) -> Array[String] {
  // Create filter config - load from project root if specified
  let mut filter = if options.root_dir.length() > 0 {
    @filter.FilterConfig::from_project_root(options.root_dir)
  } else {
    @filter.FilterConfig::new()
  }
  // Add user includes and excludes
  filter = filter
    .with_includes(options.includes)
    .with_excludes(options.excludes)
  // Add KGF ignore patterns
  for entry in options.kgf_ignore {
    filter = filter.with_kgf_ignore([entry.0], entry.1)
  }
  let file_paths : Array[String] = []
  for path in paths {
    // Expand glob patterns
    if @glob.has_glob_pattern(path) {
      let expanded = @glob.expand_glob(path)
      for expanded_path in expanded {
        collect_files_impl(expanded_path, options, filter, file_paths)
      }
    } else {
      // Skip root filter for user-specified paths — they are explicit targets,
      // not candidates for filtering (e.g., "." should not be excluded by ".*")
      collect_files_impl(
        path, options, filter, file_paths, skip_root_filter=true,
      )
    }
  }
  file_paths
}

///|
fn collect_files_impl(
  path : String,
  options : DiscoverOptions,
  filter : @filter.FilterConfig,
  file_paths : Array[String],
  skip_root_filter~ : Bool = false,
) -> Unit {
  let clean_path = trim_trailing_slash(path)
  if not(skip_root_filter) &&
    not(filter.should_include(clean_path, true).is_included()) {
    return
  }
  try {
    if @fs.is_dir(clean_path) {
      // Load nested ignore files from this directory
      let dir_filter = filter
        .with_gitignore_from_dir(clean_path)
        .with_indexionignore_from_dir(clean_path)
      let entries = @fs.read_dir(clean_path)
      for entry in entries {
        if dir_filter.should_skip_dir(entry) {
          continue
        }
        let full_path = if clean_path == "." {
          entry
        } else {
          clean_path + "/" + entry
        }
        if @fs.is_dir(full_path) {
          if options.recursive {
            collect_files_impl(full_path, options, dir_filter, file_paths)
          }
        } else if @fs.is_file(full_path) {
          // Check file inclusion using dir filter
          if dir_filter.should_include(full_path, false).is_included() {
            file_paths.push(full_path)
          }
        }
      }
    } else if @fs.is_file(clean_path) {
      file_paths.push(clean_path)
    }
  } catch {
    _ => ()
  }
}

///|
/// Default filter config, cached for performance.
/// Used by should_skip_dir for backward compatibility.
let default_filter : @filter.FilterConfig = @filter.FilterConfig::new()

///|
/// Check if directory should be skipped (hidden, build artifacts, etc.).
/// Uses cached default filter config for performance.
pub fn should_skip_dir(entry : String) -> Bool {
  default_filter.should_skip_dir(entry)
}

///|
/// Trim trailing slash from path.
pub fn trim_trailing_slash(path : String) -> String {
  if path.length() > 0 && path.has_suffix("/") {
    let chars = path.to_array()
    let result : Array[Char] = []
    for i = 0; i < chars.length() - 1; i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    path
  }
}

///|
/// Extract file basename from path.
pub fn extract_basename(path : String) -> String {
  let chars = path.to_array()
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' || chars[i] == '\\' {
      last_slash = i
    }
  }
  if last_slash >= 0 && last_slash < chars.length() - 1 {
    let out : Array[Char] = []
    for i = last_slash + 1; i < chars.length(); i = i + 1 {
      out.push(chars[i])
    }
    String::from_array(out)
  } else {
    path
  }
}

///|
/// Extract file extension from path (with dot).
pub fn extract_extension(path : String) -> String {
  let basename = extract_basename(path)
  let chars = basename.to_array()
  let mut last_dot = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '.' {
      last_dot = i
    }
  }
  if last_dot >= 0 && last_dot < chars.length() - 1 {
    let out : Array[Char] = []
    for i = last_dot; i < chars.length(); i = i + 1 {
      out.push(chars[i])
    }
    String::from_array(out)
  } else {
    ""
  }
}

///|
/// Shared glob pattern matching.
pub fn matches_pattern(text : String, pattern : String) -> Bool {
  @glob.glob_match(text, pattern)
}
