///|
/// Minimal fallback exclude patterns.
/// Language-specific patterns should be defined in KGF specs (=== ignore section).
/// These are only applied when no KGF, .gitignore, or .indexionignore patterns apply.
pub fn default_exclude_patterns() -> Array[@ignorefile.IgnorePattern] {
  [
    // Hidden directories (starting with .)
    @ignorefile.IgnorePattern::new(".*", directory_only=true, source="default"),
    // VCS directories (explicit for clarity, also matched by .*)
    dir_pattern(".git"),
    dir_pattern(".svn"),
    dir_pattern(".hg"),
  ]
}

///|
fn dir_pattern(name : String) -> @ignorefile.IgnorePattern {
  @ignorefile.IgnorePattern::new(name, directory_only=true, source="default")
}
