///|
/// Pattern parsed from a gitignore-syntax file (.gitignore, .indexionignore, etc.).
pub(all) struct IgnorePattern {
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
/// Create a new IgnorePattern with the given pattern string.
pub fn IgnorePattern::new(
  pattern : String,
  negated? : Bool = false,
  directory_only? : Bool = false,
  anchored? : Bool = false,
  source? : String = "",
) -> IgnorePattern {
  { pattern, negated, directory_only, anchored, source }
}
