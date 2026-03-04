///|
/// File discovery utilities for pipeline.
/// Consolidates file collection logic from graph and readme CLIs.

///|
/// Options for file discovery.
pub struct DiscoverOptions {
  recursive : Bool
  excludes : Array[String]
}

///|
/// Create default discover options.
pub fn DiscoverOptions::default() -> DiscoverOptions {
  { recursive: true, excludes: [] }
}

///|
/// Create discover options.
pub fn DiscoverOptions::new(
  recursive~ : Bool = true,
  excludes~ : Array[String] = [],
) -> DiscoverOptions {
  { recursive, excludes }
}

///|
/// Collect all file paths from given input paths.
/// Respects excludes and recursion settings.
pub fn discover_files(
  paths : Array[String],
  options : DiscoverOptions,
) -> Array[String] {
  let file_paths : Array[String] = []
  for path in paths {
    collect_files_impl(path, options, file_paths)
  }
  file_paths
}

///|
fn collect_files_impl(
  path : String,
  options : DiscoverOptions,
  file_paths : Array[String],
) -> Unit {
  let clean_path = trim_trailing_slash(path)
  if is_excluded(clean_path, options.excludes) {
    return
  }
  try {
    if @fs.is_dir(clean_path) {
      let entries = @fs.read_dir(clean_path)
      for entry in entries {
        if should_skip_dir(entry) {
          continue
        }
        let full_path = clean_path + "/" + entry
        if @fs.is_dir(full_path) {
          if options.recursive {
            collect_files_impl(full_path, options, file_paths)
          }
        } else if @fs.is_file(full_path) {
          file_paths.push(full_path)
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
/// Check if directory should be skipped (hidden, build artifacts, etc.).
pub fn should_skip_dir(entry : String) -> Bool {
  if entry.has_prefix(".") {
    return true
  }
  entry == "_build" || entry == ".mooncakes" || entry == "node_modules"
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
/// Check if path matches any exclude pattern.
fn is_excluded(path : String, excludes : Array[String]) -> Bool {
  for pattern in excludes {
    if matches_pattern(path, pattern) {
      return true
    }
  }
  false
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
/// Simple glob pattern matching.
pub fn matches_pattern(text : String, pattern : String) -> Bool {
  let text_chars = text.to_array()
  let pat_chars = pattern.to_array()
  matches_impl(text_chars, 0, pat_chars, 0)
}

///|
fn matches_impl(
  text : Array[Char],
  ti : Int,
  pat : Array[Char],
  pi : Int,
) -> Bool {
  if ti >= text.length() && pi >= pat.length() {
    return true
  }
  if pi >= pat.length() {
    return false
  }
  if pat[pi] == '*' {
    if matches_impl(text, ti, pat, pi + 1) {
      return true
    }
    if ti < text.length() {
      return matches_impl(text, ti + 1, pat, pi)
    }
    return false
  }
  if ti >= text.length() {
    return false
  }
  if pat[pi] == text[ti] {
    return matches_impl(text, ti + 1, pat, pi + 1)
  }
  false
}
