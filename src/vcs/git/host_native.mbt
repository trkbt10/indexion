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
async fn git_last_commit_seconds_native(root : String, path : String) -> Int? {
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
async fn git_repo_root_native(anchor : String) -> String? {
  try {
    let (exit_code, stdout) = @async_process.collect_stdout(
      "git",
      ["-C", anchor, "rev-parse", "--show-toplevel"][:],
      stderr=@async_process.redirect_to_file(null_device()),
    )
    if exit_code != 0 {
      return None
    }
    Some(stdout.text().trim().to_owned())
  } catch {
    _ => None
  }
}

///|
async fn git_head_commit_native(
  root : String,
  short? : Bool = false,
) -> String? {
  try {
    let args = if short {
      ["-C", root, "rev-parse", "--short", "HEAD"][:]
    } else {
      ["-C", root, "rev-parse", "HEAD"][:]
    }
    let (exit_code, stdout) = @async_process.collect_stdout(
      "git",
      args,
      stderr=@async_process.redirect_to_file(null_device()),
    )
    if exit_code != 0 {
      return None
    }
    Some(stdout.text().trim().to_owned())
  } catch {
    _ => None
  }
}

///|
async fn git_head_commit_seconds_native(root : String) -> Int? {
  try {
    let (exit_code, stdout) = @async_process.collect_stdout(
      "git",
      ["-C", root, "log", "-1", "--format=%ct", "HEAD"][:],
      stderr=@async_process.redirect_to_file(null_device()),
    )
    if exit_code != 0 {
      return None
    }
    parse_epoch_seconds(stdout.text())
  } catch {
    _ => None
  }
}

///|
async fn git_changed_files_native(
  root : String,
  base : String,
  paths : Array[String],
) -> Array[String]? {
  try {
    let args : Array[String] = ["-C", root, "diff", "--name-only", base, "--"]
    for path in paths {
      args.push(path)
    }
    let (exit_code, stdout) = @async_process.collect_stdout(
      "git",
      args[:],
      stderr=@async_process.redirect_to_file(null_device()),
    )
    if exit_code != 0 {
      return None
    }
    let files : Array[String] = []
    for line in stdout.text().split("\n") {
      let trimmed = line.trim().to_owned()
      if trimmed.length() > 0 {
        files.push(trimmed)
      }
    }
    files.sort()
    Some(files)
  } catch {
    _ => None
  }
}

///|
async fn git_worktree_changed_files_native(
  root : String,
  paths : Array[String],
) -> Array[String]? {
  try {
    let args : Array[String] = [
      "-C", root, "status", "--porcelain=v1", "--untracked-files=all", "--",
    ]
    for path in paths {
      args.push(path)
    }
    let (exit_code, stdout) = @async_process.collect_stdout(
      "git",
      args[:],
      stderr=@async_process.redirect_to_file(null_device()),
    )
    if exit_code != 0 {
      return None
    }
    let files : Array[String] = []
    for line in stdout.text().split("\n") {
      let trimmed = line.trim().to_owned()
      if trimmed.length() < 4 {
        continue
      }
      let path = @config_paths.substring_from(trimmed, 3)
      if path.length() > 0 {
        files.push(path)
      }
    }
    files.sort()
    Some(files)
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
