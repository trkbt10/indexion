///|

///|
#borrow(root)
extern "C" fn c_git_is_repo(root : Bytes, root_len : Int) -> Int = "indexion_git_is_repo"

///|
#borrow(root, path)
extern "C" fn c_git_status_dirty(
  root : Bytes,
  root_len : Int,
  path : Bytes,
  path_len : Int,
) -> Int = "indexion_git_status_dirty"

///|
#borrow(root, path)
extern "C" fn c_git_last_commit_seconds(
  root : Bytes,
  root_len : Int,
  path : Bytes,
  path_len : Int,
) -> Int64 = "indexion_git_last_commit_seconds"

///|
fn encode_path(text : String) -> Bytes {
  @utf8.encode(text)
}

///|
fn git_is_repo_native(root : String) -> Bool {
  let root_bytes = encode_path(root)
  c_git_is_repo(root_bytes, root_bytes.length()) == 1
}

///|
fn git_status_dirty_native(root : String, path : String) -> Bool {
  let root_bytes = encode_path(root)
  let path_bytes = encode_path(path)
  c_git_status_dirty(
    root_bytes,
    root_bytes.length(),
    path_bytes,
    path_bytes.length(),
  ) ==
  1
}

///|
fn git_last_commit_seconds_native(root : String, path : String) -> Int? {
  let root_bytes = encode_path(root)
  let path_bytes = encode_path(path)
  let seconds = c_git_last_commit_seconds(
    root_bytes,
    root_bytes.length(),
    path_bytes,
    path_bytes.length(),
  )
  if seconds < 0L {
    None
  } else {
    Some(seconds.to_int())
  }
}

///|
/// Return the file modification time in seconds, or None if unavailable.
pub async fn file_mtime_seconds(path : String) -> Int? {
  try {
    let (seconds, _nanoseconds) = @async_fs.mtime(path)
    Some(seconds.to_int())
  } catch {
    _ => None
  }
}
