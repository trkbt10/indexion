///|
/// Check whether the given root directory is a Git repository.
pub async fn is_repo(_root : String) -> Bool {
  git_is_repo_native(_root)
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
pub async fn status_dirty(_root : String, _path : String) -> Bool {
  git_status_dirty_native(_root, query_path(_root, _path))
}

///|
/// Return the last commit timestamp in seconds for the given path, or None on failure.
pub async fn last_commit_seconds(_root : String, _path : String) -> Int? {
  git_last_commit_seconds_native(_root, query_path(_root, _path))
}

///|
pub async fn repo_root(_anchor : String) -> String? {
  git_repo_root_native(_anchor)
}

///|
pub async fn head_commit(_root : String, short? : Bool = false) -> String? {
  git_head_commit_native(_root, short~)
}

///|
pub async fn head_commit_seconds(_root : String) -> Int? {
  git_head_commit_seconds_native(_root)
}

///|
pub async fn changed_files(
  _root : String,
  _base : String,
  _paths : Array[String],
) -> Array[String]? {
  let rel_paths = _paths
    .iter()
    .map(fn(path) { query_path(_root, path) })
    .collect()
  git_changed_files_native(_root, _base, rel_paths)
}

///|
pub async fn worktree_changed_files(
  _root : String,
  _paths : Array[String],
) -> Array[String]? {
  let rel_paths = _paths
    .iter()
    .map(fn(path) { query_path(_root, path) })
    .collect()
  git_worktree_changed_files_native(_root, rel_paths)
}
