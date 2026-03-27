///|
/// .indexionignore loading with hoisting from indexion project root.
/// The indexion project root is identified by .indexion/, .indexion.toml, or .indexion.json.

///|
/// Indexion-specific ignore filename.
pub const INDEXIONIGNORE_FILENAME : String = ".indexionignore"

///|
/// Markers that identify an indexion project root.
let indexion_root_markers : Array[String] = [
  ".indexion", ".indexion.toml", ".indexion.json",
]

///|
/// Load .indexionignore patterns with hoisting from indexion project root
/// down to the target directory.
pub fn load_indexionignore(
  target_dir : String,
) -> Array[@ignorefile.IgnorePattern] {
  let patterns : Array[@ignorefile.IgnorePattern] = []
  let root = find_project_root(target_dir, indexion_root_markers)
  let dirs = match root {
    Some(r) => ancestors_top_down(target_dir, r)
    None => [target_dir]
  }
  for dir in dirs {
    let loaded = @ignorefile.load_from_dir(dir, INDEXIONIGNORE_FILENAME)
    for p in loaded {
      patterns.push(p)
    }
  }
  patterns
}
