///|
/// Filter configuration for file discovery.
/// Pure data structure — no file I/O. Constructed by callers
/// who load ignore patterns from appropriate sources.
pub struct FilterConfig {
  /// Default exclude patterns (built-in, lowest priority fallback)
  default_excludes : Array[@ignorefile.IgnorePattern]
  /// Patterns from KGF specs (language-specific)
  kgf_ignore_patterns : Array[@ignorefile.IgnorePattern]
  /// Patterns from .gitignore files
  gitignore_patterns : Array[@ignorefile.IgnorePattern]
  /// Patterns from .indexionignore
  indexionignore_patterns : Array[@ignorefile.IgnorePattern]
  /// CLI --include patterns (highest priority)
  user_includes : Array[String]
  /// CLI --exclude patterns (highest priority)
  user_excludes : Array[String]
  /// Whether to respect .gitignore files
  respect_gitignore : Bool
}

///|
/// Create a new FilterConfig with default settings.
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
/// Create a FilterConfig with user-specified include/exclude patterns.
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
      @ignorefile.IgnorePattern::new(
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
/// Add pre-loaded gitignore patterns.
pub fn FilterConfig::with_gitignore_patterns(
  self : FilterConfig,
  patterns : Array[@ignorefile.IgnorePattern],
) -> FilterConfig {
  let new_patterns = self.gitignore_patterns.copy()
  for p in patterns {
    new_patterns.push(p)
  }
  { ..self, gitignore_patterns: new_patterns }
}

///|
/// Add pre-loaded indexionignore patterns.
pub fn FilterConfig::with_indexionignore_patterns(
  self : FilterConfig,
  patterns : Array[@ignorefile.IgnorePattern],
) -> FilterConfig {
  let new_patterns = self.indexionignore_patterns.copy()
  for p in patterns {
    new_patterns.push(p)
  }
  { ..self, indexionignore_patterns: new_patterns }
}

///|
/// Load a gitignore-syntax file from a directory and merge into gitignore patterns.
/// Callers must pass the filename from their domain's SoT constant.
pub fn FilterConfig::with_gitignore_from_dir(
  self : FilterConfig,
  dir_path : String,
  filename : String,
) -> FilterConfig {
  let patterns = @ignorefile.load_from_dir(dir_path, filename)
  if patterns.is_empty() {
    return self
  }
  self.with_gitignore_patterns(patterns)
}

///|
/// Load a gitignore-syntax file from a directory and merge into indexionignore patterns.
/// Callers must pass the filename from their domain's SoT constant.
pub fn FilterConfig::with_indexionignore_from_dir(
  self : FilterConfig,
  dir_path : String,
  filename : String,
) -> FilterConfig {
  let patterns = @ignorefile.load_from_dir(dir_path, filename)
  if patterns.is_empty() {
    return self
  }
  self.with_indexionignore_patterns(patterns)
}

///|
/// Result of filtering a path.
pub enum FilterResult {
  Include
  Exclude(String) // Reason for exclusion
} derive(Eq, Show)

///|
/// Check if the result indicates the path should be included.
pub fn FilterResult::is_included(self : FilterResult) -> Bool {
  match self {
    Include => true
    Exclude(_) => false
  }
}
