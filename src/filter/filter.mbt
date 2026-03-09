///|
/// Check if a path should be included based on filter configuration.
/// Priority (highest to lowest):
/// 1. User --exclude (forces exclusion, highest priority)
/// 2. User --include (whitelist mode when specified)
/// 3. Project ignore file (INDEXIONIGNORE_FILENAME)
/// 4. Git ignore file (GITIGNORE_FILENAME)
/// 5. KGF ignore patterns (language-specific)
/// 6. Default excludes (fallback)
pub fn FilterConfig::should_include(
  self : FilterConfig,
  path : String,
  is_dir : Bool,
) -> FilterResult {
  let config = self
  let basename = get_basename(path)
  // 1. Check user excludes first (highest priority - forces exclusion)
  for pattern in config.user_excludes {
    if glob_match(path, pattern) || glob_match(basename, pattern) {
      return Exclude("user --exclude: " + pattern)
    }
  }
  // 2. Check user includes (whitelist mode when specified)
  // If --include is specified, only matching files are included
  if config.user_includes.length() > 0 {
    let mut matched = false
    for pattern in config.user_includes {
      if glob_match(path, pattern) || glob_match(basename, pattern) {
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
    INDEXIONIGNORE_FILENAME,
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
      GITIGNORE_FILENAME,
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
  patterns : Array[IgnorePattern],
  path : String,
  is_dir : Bool,
  source_name : String,
) -> FilterResult? {
  let mut last_match : FilterResult? = None
  for pattern in patterns {
    if pattern_matches(pattern, path, is_dir) {
      if pattern.negated {
        last_match = Some(Include)
      } else {
        last_match = Some(Exclude(source_name + ": " + pattern.pattern))
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
    if glob_match(dir_name, pattern) {
      return false
    }
  }
  // Check user excludes
  for pattern in config.user_excludes {
    if glob_match(dir_name, pattern) {
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
