///|
async fn git_is_repo_native(_root : String) -> Bool {
  false
}

///|
async fn git_status_dirty_native(_root : String, _path : String) -> Bool {
  false
}

///|
async fn git_last_commit_seconds_native(_root : String, _path : String) -> Int? {
  None
}

///|
/// Return the file modification time in seconds, or None if unavailable.
pub async fn file_mtime_seconds(_path : String) -> Int? {
  None
}
