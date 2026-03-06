///|
/// Pattern for file/directory filtering.
pub struct IgnorePattern {
  /// The glob pattern (e.g., "*.log", "_build/", "**/node_modules")
  pattern : String
  /// If true, this pattern un-ignores (negates) matching files
  negated : Bool
  /// If true, only matches directories (pattern ends with /)
  directory_only : Bool
  /// If true, pattern is anchored to root (starts with / or contains /)
  anchored : Bool
  /// Source file this pattern came from (e.g., ".gitignore")
  source : String
}

///|
pub fn IgnorePattern::new(
  pattern : String,
  negated? : Bool = false,
  directory_only? : Bool = false,
  anchored? : Bool = false,
  source? : String = "",
) -> IgnorePattern {
  { pattern, negated, directory_only, anchored, source }
}

///|
/// Filter configuration for file discovery.
pub struct FilterConfig {
  /// Default exclude patterns (built-in, lowest priority fallback)
  default_excludes : Array[IgnorePattern]
  /// Patterns from KGF specs (language-specific)
  kgf_ignore_patterns : Array[IgnorePattern]
  /// Patterns from .gitignore files
  gitignore_patterns : Array[IgnorePattern]
  /// Patterns from .indexionignore
  indexionignore_patterns : Array[IgnorePattern]
  /// CLI --include patterns (highest priority)
  user_includes : Array[String]
  /// CLI --exclude patterns (highest priority)
  user_excludes : Array[String]
  /// Whether to respect .gitignore files
  respect_gitignore : Bool
}

///|
pub fn FilterConfig::new() -> FilterConfig {
  {
    default_excludes: default_exclude_patterns(),
    kgf_ignore_patterns: [],
    gitignore_patterns: [],
    indexionignore_patterns: [],
    user_includes: [],
    user_excludes: [],
    respect_gitignore: true,
  }
}

///|
pub fn FilterConfig::with_user_patterns(
  includes : Array[String],
  excludes : Array[String],
) -> FilterConfig {
  {
    default_excludes: default_exclude_patterns(),
    kgf_ignore_patterns: [],
    gitignore_patterns: [],
    indexionignore_patterns: [],
    user_includes: includes,
    user_excludes: excludes,
    respect_gitignore: true,
  }
}

///|
/// Add ignore patterns from a KGF spec.
pub fn FilterConfig::with_kgf_ignore(
  self : FilterConfig,
  patterns : Array[String],
  language : String,
) -> FilterConfig {
  let new_patterns = self.kgf_ignore_patterns.copy()
  for p in patterns {
    // Parse pattern (supports trailing / for directories)
    let (pattern, dir_only) = if p.has_suffix("/") {
      let chars = p.to_array()
      let trimmed : Array[Char] = []
      for i = 0; i < chars.length() - 1; i = i + 1 {
        trimmed.push(chars[i])
      }
      (String::from_array(trimmed), true)
    } else {
      (p, false)
    }
    new_patterns.push(
      IgnorePattern::new(
        pattern,
        directory_only=dir_only,
        source="kgf:" + language,
      ),
    )
  }
  { ..self, kgf_ignore_patterns: new_patterns }
}

///|
/// Add include patterns to the config.
pub fn FilterConfig::with_includes(
  self : FilterConfig,
  patterns : Array[String],
) -> FilterConfig {
  let new_includes = self.user_includes.copy()
  for p in patterns {
    new_includes.push(p)
  }
  { ..self, user_includes: new_includes }
}

///|
/// Add exclude patterns to the config.
pub fn FilterConfig::with_excludes(
  self : FilterConfig,
  patterns : Array[String],
) -> FilterConfig {
  let new_excludes = self.user_excludes.copy()
  for p in patterns {
    new_excludes.push(p)
  }
  { ..self, user_excludes: new_excludes }
}

///|
/// Load FilterConfig from project root, reading gitignore and indexionignore.
pub fn FilterConfig::from_project_root(root_dir : String) -> FilterConfig {
  let config = FilterConfig::new()
  // Load gitignore
  let gitignore_path = root_dir + "/" + GITIGNORE_FILENAME
  try {
    let content = @fs.read_file_to_string(gitignore_path)
    let patterns = parse_ignore_file(content, gitignore_path)
    for p in patterns {
      config.gitignore_patterns.push(p)
    }
  } catch {
    _ => ()
  }
  // Load indexionignore
  let indexionignore_path = root_dir + "/" + INDEXIONIGNORE_FILENAME
  try {
    let content = @fs.read_file_to_string(indexionignore_path)
    let patterns = parse_ignore_file(content, indexionignore_path)
    for p in patterns {
      config.indexionignore_patterns.push(p)
    }
  } catch {
    _ => ()
  }
  config
}

///|
/// Load gitignore from a directory and merge into config.
/// Used for nested gitignore support during traversal.
pub fn FilterConfig::with_gitignore_from_dir(
  self : FilterConfig,
  dir_path : String,
) -> FilterConfig {
  let gitignore_path = dir_path + "/" + GITIGNORE_FILENAME
  try {
    let content = @fs.read_file_to_string(gitignore_path)
    let patterns = parse_ignore_file(content, gitignore_path)
    if patterns.is_empty() {
      return self
    }
    let new_patterns = self.gitignore_patterns.copy()
    for p in patterns {
      new_patterns.push(p)
    }
    { ..self, gitignore_patterns: new_patterns }
  } catch {
    _ => self
  }
}

///|
/// Load indexionignore from a directory and merge into config.
pub fn FilterConfig::with_indexionignore_from_dir(
  self : FilterConfig,
  dir_path : String,
) -> FilterConfig {
  let ignore_path = dir_path + "/" + INDEXIONIGNORE_FILENAME
  try {
    let content = @fs.read_file_to_string(ignore_path)
    let patterns = parse_ignore_file(content, ignore_path)
    if patterns.is_empty() {
      return self
    }
    let new_patterns = self.indexionignore_patterns.copy()
    for p in patterns {
      new_patterns.push(p)
    }
    { ..self, indexionignore_patterns: new_patterns }
  } catch {
    _ => self
  }
}

///|
/// Result of filtering a path.
pub enum FilterResult {
  Include
  Exclude(String) // Reason for exclusion
} derive(Eq, Show)

///|
pub fn FilterResult::is_included(self : FilterResult) -> Bool {
  match self {
    Include => true
    Exclude(_) => false
  }
}
