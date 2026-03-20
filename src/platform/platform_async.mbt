///|
/// Platform-dependent async operations.
/// Only functions that branch on detect_platform() belong here.

///|
/// Make a file executable. No-op on Windows.
pub async fn make_executable(path : String) -> Unit {
  match detect_platform() {
    Windows => ()
    _ => {
      let _ = @async_process.run("chmod", ["+x", path][:])
    }
  }
}

///|
/// Install a binary, handling the Windows in-use executable problem.
/// On Windows: read new binary first, rename old to .old, write new, rollback on failure.
/// On Unix: direct copy (overwrite is allowed even for running binaries).
pub async fn install_binary(src : String, dst : String) -> Unit {
  match detect_platform() {
    Windows => {
      // Read new binary BEFORE touching the existing one
      let data = @async_fs.read_file(src)
      let dst_exists = @async_fs.exists(dst)
      let old_path = dst + ".old"
      if dst_exists {
        // Remove previous .old if it exists
        let old_exists = @async_fs.exists(old_path)
        if old_exists {
          @async_fs.remove(old_path)
        }
        // Rename running binary out of the way (cmd /c move allows renaming in-use exe)
        let exit_code = @async_process.run(
          "cmd",
          ["/c", "move", "/Y", dst, old_path][:],
        )
        if exit_code != 0 {
          fail("Failed to rename existing binary (exit code \{exit_code})")
        }
      }
      // Write new binary; rollback on failure
      @async_fs.write_file(dst, data, create=0o644) catch {
        e => {
          // Rollback: restore old binary
          if dst_exists {
            let _ = @async_process.run(
              "cmd",
              ["/c", "move", "/Y", old_path, dst][:],
            )
          }
          raise e
        }
      }
    }
    _ => {
      let data = @async_fs.read_file(src)
      @async_fs.write_file(dst, data, create=0o644)
    }
  }
}

///|
/// Extract an archive to a destination directory.
/// This is the only platform-dependent shell operation.
/// Unix: tar -xzf, Windows: powershell Expand-Archive
pub async fn extract_archive(archive : String, dest : String) -> Unit {
  let exit_code = match detect_platform() {
    Windows =>
      @async_process.run(
        "powershell",
        [
          "-Command", "Expand-Archive", "-Path", archive, "-DestinationPath", dest,
          "-Force",
        ][:],
      )
    _ => @async_process.run("tar", ["-xzf", archive, "-C", dest][:])
  }
  if exit_code != 0 {
    fail("extract_archive failed with exit code \{exit_code}")
  }
}
