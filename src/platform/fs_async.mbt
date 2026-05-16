///|
/// Async filesystem operations (read, write, copy, mkdir, remove).
/// Platform-independent; no detect_platform() branching.

///|
fn path_join(base : String, child : StringView) -> String {
  let suffix = child.to_owned()
  if base.has_suffix("/") {
    base + suffix
  } else {
    base + "/" + suffix
  }
}

///|
/// Copy a single file (async read + write).
pub async fn copy_file(src : String, dst : String) -> Unit {
  let data = @async_fs.read_file(src)
  @async_fs.write_file(dst, data, create=0o644)
}

///|
/// Copy a directory recursively (readdir + mkdir + copy_file).
pub async fn copy_dir_recursive(src : String, dst : String) -> Unit {
  @async_fs.mkdir(dst, permission=0o755, recursive=true)
  let entries = @async_fs.readdir(src)
  let mut i = 0
  while i < entries.length() {
    let entry = entries[i]
    let src_path = path_join(src, entry)
    let dst_path = path_join(dst, entry)
    let k = @async_fs.kind(src_path)
    match k {
      Directory => copy_dir_recursive(src_path, dst_path)
      Regular => {
        let data = @async_fs.read_file(src_path)
        @async_fs.write_file(dst_path, data, create=0o644)
      }
      _ => ()
    }
    i = i + 1
  }
}

///|
/// Create a temporary directory with the given prefix.
pub async fn create_temp_dir(prefix : String) -> String {
  @async_fs.tmpdir(prefix~)
}

///|
/// Remove a directory and all its contents.
pub async fn remove_dir_recursive(path : String) -> Unit {
  @async_fs.rmdir(path, recursive=true)
}

///|
/// Check if a path exists (async).
pub async fn path_exists_async(path : String) -> Bool {
  @async_fs.exists(path)
}

///|
/// Write bytes to a file (async).
pub async fn write_bytes_async(path : String, data : Bytes) -> Unit {
  @async_fs.write_file(path, data, create=0o644)
}

///|
/// Ensure a directory exists, creating it recursively if needed (async).
pub async fn ensure_dir_async(path : String) -> Unit {
  let exists = @async_fs.exists(path)
  if !exists {
    @async_fs.mkdir(path, permission=0o755, recursive=true)
  }
}
