///|
/// Parse an epoch timestamp (seconds) from git output text.
fn parse_epoch_seconds(text : String) -> Int? {
  let mut result = 0
  let mut seen_digit = false
  for ch in text {
    if ch >= '0' && ch <= '9' {
      seen_digit = true
      result = result * 10 + (ch.to_int() - 48)
    } else if ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t' {
      if seen_digit {
        break
      }
    } else {
      return None
    }
  }
  if seen_digit {
    Some(result)
  } else {
    None
  }
}

///|
/// Return the platform-appropriate null device path.
fn null_device() -> String {
  match @platform.detect_platform() {
    Windows => "NUL"
    _ => "/dev/null"
  }
}

///|
async fn git_is_repo_native(root : String) -> Bool {
  try {
    let devnull = @async_process.redirect_to_file(null_device())
    let exit_code = @async_process.run(
      "git",
      ["-C", root, "rev-parse", "--is-inside-work-tree"][:],
      stdout=devnull,
      stderr=@async_process.redirect_to_file(null_device()),
    )
    exit_code == 0
  } catch {
    _ => false
  }
}

///|
async fn git_status_dirty_native(root : String, path : String) -> Bool {
  try {
    let (exit_code, stdout) = @async_process.collect_stdout(
      "git",
      ["-C", root, "status", "--porcelain=v1", "--", path][:],
      stderr=@async_process.redirect_to_file(null_device()),
    )
    if exit_code != 0 {
      return false
    }
    let output = stdout.text()
    output.length() > 0
  } catch {
    _ => false
  }
}

///|
async fn git_last_commit_seconds_native(
  root : String,
  path : String,
) -> Int? {
  try {
    let (exit_code, stdout) = @async_process.collect_stdout(
      "git",
      ["-C", root, "log", "-1", "--format=%ct", "--", path][:],
      stderr=@async_process.redirect_to_file(null_device()),
    )
    if exit_code != 0 {
      return None
    }
    let output = stdout.text()
    parse_epoch_seconds(output)
  } catch {
    _ => None
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
