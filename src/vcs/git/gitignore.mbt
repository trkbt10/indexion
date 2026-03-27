///|
/// .gitignore loading with hoisting from git repository root.
/// The git root is identified by .git (directory for normal repos, file for submodules).

///|
/// Standard git ignore filename.
pub const GITIGNORE_FILENAME : String = ".gitignore"

///|
/// Markers that identify a git repository root.
let git_root_markers : Array[String] = [".git"]

///|
/// Load .gitignore patterns with hoisting from git root
/// down to the target directory.
pub fn load_gitignore(target_dir : String) -> Array[@ignorefile.IgnorePattern] {
  let patterns : Array[@ignorefile.IgnorePattern] = []
  let root = @config_paths.find_project_root(target_dir, git_root_markers)
  let dirs = match root {
    Some(r) => @config_paths.ancestors_top_down(target_dir, r)
    None => [target_dir]
  }
  for dir in dirs {
    let loaded = @ignorefile.load_from_dir(dir, GITIGNORE_FILENAME)
    for p in loaded {
      patterns.push(p)
    }
  }
  patterns
}
