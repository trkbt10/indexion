///|
/// Check if path matches an ignore pattern, handling directory-only semantics.
pub fn pattern_matches(
  pattern : @ignorefile.IgnorePattern,
  path : String,
  is_dir : Bool,
) -> Bool {
  let p = pattern.pattern
  if pattern.directory_only {
    if is_dir {
      if pattern.anchored {
        return @glob.glob_match(path, p)
      }
      let basename = path_basename(path)
      if @glob.glob_match(basename, p) {
        return true
      }
      return @glob.glob_match_anywhere(path, p)
    }
    if pattern.anchored {
      return @glob.glob_match(path, p + "/**")
    }
    return path_starts_with_pattern(path, p)
  }
  if pattern.anchored {
    return @glob.glob_match(path, p)
  }
  let basename = path_basename(path)
  if @glob.glob_match(basename, p) {
    return true
  }
  @glob.glob_match_anywhere(path, p)
}

///|
/// Check if a path should be included based on filter configuration.
/// Priority (highest to lowest):
/// 1. User --exclude (forces exclusion, highest priority)
/// 2. User --include (whitelist mode when specified)
/// 3. Project ignore file (".indexionignore")
/// 4. Git ignore file (".gitignore")
/// 5. KGF ignore patterns (language-specific)
/// 6. Default excludes (fallback)
pub fn FilterConfig::should_include(
  self : FilterConfig,
  path : String,
  is_dir : Bool,
) -> FilterResult {
  let config = self
  let basename = path_basename(path)
  // 1. Check user excludes first (highest priority - forces exclusion)
  for pattern in config.user_excludes {
    if @glob.glob_match(path, pattern) || @glob.glob_match(basename, pattern) {
      return Exclude("user --exclude: " + pattern)
    }
  }
  // 2. Check user includes (whitelist mode when specified)
  // If --include is specified, only matching files are included
  // Follows gitignore semantics:
  //   - Pattern without "/" = filename pattern (matches basename anywhere)
  //   - Pattern with "/" = path pattern (matches against full path)
  //   - Filename patterns don't apply to directories (not a match target)
  //   - Path patterns allow directory traversal if dir is on the path to matches
  if config.user_includes.length() > 0 {
    let mut matched = false
    for pattern in config.user_includes {
      // Check if this is a filename pattern (no slash) or path pattern
      let is_filename_pattern = not(contains_slash(pattern))
      if is_dir {
        // For directories, check if traversal should continue
        if is_filename_pattern {
          // Filename pattern: directory is not a target, continue traversal
          matched = true
          break
        }
        // Path pattern: check if directory is on the path to potential matches
        if dir_could_contain_pattern_match(path, pattern) {
          matched = true
          break
        }
        // For files, check pattern match
      } else if @glob.glob_match(path, pattern) ||
        @glob.glob_match(basename, pattern) {
        matched = true
        break
      }
    }
    if not(matched) {
      return Exclude("user --include: no match")
    }
    // Matched include pattern - continue to check other rules
    // (already passed exclude check above)
    return Include
  }
  // 3. Check indexionignore (process all patterns, last match wins)
  let indexion_result = check_ignore_patterns(
    config.indexionignore_patterns,
    path,
    is_dir,
  )
  match indexion_result {
    Some(result) => return result
    None => ()
  }
  // 4. Check gitignore (if enabled, process all patterns, last match wins)
  if config.respect_gitignore {
    let git_result = check_ignore_patterns(
      config.gitignore_patterns,
      path,
      is_dir,
    )
    match git_result {
      Some(result) => return result
      None => ()
    }
  }
  // 5. Check KGF ignore patterns (language-specific)
  for pattern in config.kgf_ignore_patterns {
    if pattern_matches(pattern, path, is_dir) {
      return Exclude(pattern.source + ": " + pattern.pattern)
    }
  }
  // 6. Check default excludes (fallback)
  for pattern in config.default_excludes {
    if pattern_matches(pattern, path, is_dir) {
      return Exclude("default: " + pattern.pattern)
    }
  }
  // Not excluded - include
  Include
}

///|
/// Check ignore patterns with proper negation handling.
/// Returns Some(result) if any pattern matches, None otherwise.
/// Later patterns override earlier ones (gitignore semantics).
fn check_ignore_patterns(
  patterns : Array[@ignorefile.IgnorePattern],
  path : String,
  is_dir : Bool,
) -> FilterResult? {
  let mut last_match : FilterResult? = None
  for pattern in patterns {
    if pattern_matches(pattern, path, is_dir) {
      if pattern.negated {
        last_match = Some(Include)
      } else {
        last_match = Some(Exclude(pattern.source + ": " + pattern.pattern))
      }
    }
  }
  last_match
}

///|
/// Check if a directory should be skipped during traversal.
/// This is used for early termination - if a directory is excluded,
/// we don't need to traverse into it.
/// Uses same priority as should_include but for directories only.
pub fn FilterConfig::should_skip_dir(
  self : FilterConfig,
  dir_name : String,
) -> Bool {
  let config = self
  // Check user includes first (if matched, don't skip)
  for pattern in config.user_includes {
    if @glob.glob_match(dir_name, pattern) {
      return false
    }
  }
  // Check user excludes
  for pattern in config.user_excludes {
    if @glob.glob_match(dir_name, pattern) {
      return true
    }
  }
  // Check indexionignore patterns
  for pattern in config.indexionignore_patterns {
    if pattern_matches(pattern, dir_name, true) {
      if pattern.negated {
        return false
      } else {
        return true
      }
    }
  }
  // Check gitignore patterns
  for pattern in config.gitignore_patterns {
    if pattern_matches(pattern, dir_name, true) {
      if pattern.negated {
        return false
      } else {
        return true
      }
    }
  }
  // Check KGF ignore patterns (language-specific)
  for pattern in config.kgf_ignore_patterns {
    if pattern_matches(pattern, dir_name, true) {
      return true
    }
  }
  // Check default excludes (fallback)
  for pattern in config.default_excludes {
    if pattern_matches(pattern, dir_name, true) {
      return true
    }
  }
  false
}

///|
/// Filter a list of paths using the configuration.
pub fn filter_paths(
  config : FilterConfig,
  paths : Array[String],
  is_dir_fn : (String) -> Bool,
) -> Array[String] {
  let result : Array[String] = []
  for path in paths {
    let is_dir = is_dir_fn(path)
    if config.should_include(path, is_dir).is_included() {
      result.push(path)
    }
  }
  result
}

///|
/// Check if a directory could contain files that match a path pattern.
/// For pattern "src/filter/*.mbt":
///   - dir "src" → true (prefix of pattern's directory)
///   - dir "src/filter" → true (matches pattern's directory)
///   - dir "src/core" → false (not on the path)
fn dir_could_contain_pattern_match(dir : String, pattern : String) -> Bool {
  // Normalize: ensure dir ends with /
  let dir_with_slash = if dir.has_suffix("/") { dir } else { dir + "/" }
  // Extract the fixed prefix of the pattern (before wildcards)
  let pattern_prefix = extract_pattern_prefix(pattern)
  let prefix_with_slash = if pattern_prefix.has_suffix("/") {
    pattern_prefix
  } else {
    pattern_prefix + "/"
  }
  // Check if dir is a prefix of the pattern's directory part
  // e.g., "src/" is prefix of "src/filter/"
  if prefix_with_slash.has_prefix(dir_with_slash) {
    return true
  }
  // Check if pattern's prefix is a prefix of dir
  // e.g., "src/filter/" is prefix of "src/filter/sub/"
  if dir_with_slash.has_prefix(prefix_with_slash) {
    return true
  }
  // Also check with ** patterns - if pattern contains **, be more permissive
  if pattern.has_prefix("**/") || pattern.has_prefix("**\\") {
    // Pattern like "**/test.mbt" matches anywhere
    return true
  }
  false
}

///|
/// Check if string contains a slash.
fn contains_slash(s : String) -> Bool {
  for c in s {
    if c == '/' {
      return true
    }
  }
  false
}

///|
fn path_basename(path : String) -> String {
  let chars = path.to_array()
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last_slash = i
    }
  }
  if last_slash < 0 {
    path
  } else {
    @parser.substr_from(path, last_slash + 1)
  }
}

///|
fn path_starts_with_pattern(path : String, pattern : String) -> Bool {
  let path_chars = path.to_array()
  for i = 0; i <= path_chars.length(); i = i + 1 {
    if i == 0 || (i > 0 && path_chars[i - 1] == '/') {
      let suffix = @parser.substr_from(path, i)
      if @glob.glob_match(suffix, pattern + "/**") ||
        @glob.glob_match(suffix, pattern + "/*") {
        return true
      }
    }
  }
  false
}

///|
/// Extract the fixed prefix of a glob pattern (before any wildcards).
/// "src/filter/*.mbt" → "src/filter"
/// "src/**/test.mbt" → "src"
/// "*.mbt" → ""
fn extract_pattern_prefix(pattern : String) -> String {
  let chars = pattern.to_array()
  let result : Array[Char] = []
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    // Stop at first wildcard character
    if c == '*' || c == '?' || c == '[' {
      break
    }
    result.push(c)
    if c == '/' || c == '\\' {
      last_slash = result.length()
    }
  }
  // Return up to the last slash (directory part only)
  if last_slash > 0 {
    let dir_part : Array[Char] = []
    for i = 0; i < last_slash; i = i + 1 {
      dir_part.push(result[i])
    }
    String::from_array(dir_part)
  } else {
    String::from_array(result)
  }
}
