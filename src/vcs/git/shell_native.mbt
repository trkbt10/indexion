///|
/// Check whether the given root directory is a Git repository.
pub async fn is_repo(root : String) -> Bool {
  git_is_repo_native(root)
}

///|
/// Compute the relative path from the repository root for Git queries.
pub fn query_path(root : String, path : String) -> String {
  if path == "." {
    return "."
  }
  let rel = @config_paths.relative_to(root, path)
  if rel.length() == 0 {
    "."
  } else {
    rel
  }
}

///|
/// Return whether the given path has uncommitted changes in the Git working tree.
pub async fn status_dirty(root : String, path : String) -> Bool {
  git_status_dirty_native(root, query_path(root, path))
}

///|
/// Return the last commit timestamp in seconds for the given path, or None on failure.
pub async fn last_commit_seconds(root : String, path : String) -> Int? {
  git_last_commit_seconds_native(root, query_path(root, path))
}

///|
/// Resolve the repository root containing the anchor path.
pub async fn repo_root(anchor : String) -> String? {
  git_repo_root_native(anchor)
}

///|
/// Return the current HEAD commit for the repository root.
pub async fn head_commit(root : String, short? : Bool = false) -> String? {
  git_head_commit_native(root, short~)
}

///|
/// Return the current HEAD commit timestamp in seconds.
pub async fn head_commit_seconds(root : String) -> Int? {
  git_head_commit_seconds_native(root)
}

///|
/// Return changed files under the given relative paths from the base ref.
pub async fn changed_files(
  root : String,
  base : String,
  paths : Array[String],
) -> Array[String]? {
  let rel_paths = paths
    .iter()
    .map(fn(path) { query_path(root, path) })
    .collect()
  git_changed_files_native(root, base, rel_paths)
}

///|
/// Return changed working-tree files under the given paths.
pub async fn worktree_changed_files(
  root : String,
  paths : Array[String],
) -> Array[String]? {
  let rel_paths = paths
    .iter()
    .map(fn(path) { query_path(root, path) })
    .collect()
  git_worktree_changed_files_native(root, rel_paths)
}
