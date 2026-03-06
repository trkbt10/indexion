///|
/// Minimal fallback exclude patterns.
/// Language-specific patterns should be defined in KGF specs (=== ignore section).
/// These are only applied when no KGF, .gitignore, or .indexionignore patterns apply.
pub fn default_exclude_patterns() -> Array[IgnorePattern] {
  [
    // Hidden directories (starting with .)
    IgnorePattern::new(".*", directory_only=true, source="default"),
    // VCS directories (explicit for clarity, also matched by .*)
    dir_pattern(".git"),
    dir_pattern(".svn"),
    dir_pattern(".hg"),
  ]
}

///|
/// Create a directory-only pattern.
fn dir_pattern(name : String) -> IgnorePattern {
  IgnorePattern::new(name, directory_only=true, source="default")
}

