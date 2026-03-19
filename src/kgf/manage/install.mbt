///|
/// Install kgfs from a source directory to the OS-standard data directory.
/// This is the SoT for kgfs installation — both `indexion update` and
/// `indexion kgf update` delegate here.
pub async fn install_kgfs_from_dir(
  src_kgfs : String,
) -> Unit raise KgfManageError {
  let data_dir = match @config.get_global_data_dir() {
    Some(dir) => dir
    None =>
      match @config.get_install_dir() {
        Some(dir) => dir
        None =>
          raise KgfManageError::InstallError("Cannot determine data directory")
      }
  }
  let dst_kgfs = @config.join_path(data_dir, "kgfs")
  @platform.ensure_dir_async(data_dir) catch {
    err =>
      raise KgfManageError::InstallError(
        "Failed to create data directory: " + err.to_string(),
      )
  }
  let old_exists = @platform.path_exists_async(dst_kgfs) catch { _ => false }
  if old_exists {
    @platform.remove_dir_recursive(dst_kgfs) catch {
      err =>
        raise KgfManageError::InstallError(
          "Failed to remove old kgfs: " + err.to_string(),
        )
    }
  }
  @platform.copy_dir_recursive(src_kgfs, dst_kgfs) catch {
    err =>
      raise KgfManageError::InstallError(
        "Failed to copy kgfs: " + err.to_string(),
      )
  }
  println("KGF specs installed to " + dst_kgfs)
}

///|
/// Install a single .kgf file to the OS-standard data directory.
/// `relative_path` is the path within the kgfs directory (e.g., "programming/go.kgf").
pub async fn install_single_kgf(
  relative_path : String,
  content : Bytes,
) -> Unit raise KgfManageError {
  let data_dir = match @config.get_global_data_dir() {
    Some(dir) => dir
    None =>
      raise KgfManageError::InstallError("Cannot determine data directory")
  }
  let dst_path = @config.join_path(
    @config.join_path(data_dir, "kgfs"),
    relative_path,
  )
  // Ensure parent directory exists
  let parent = @config.dirname(dst_path)
  @platform.ensure_dir_async(parent) catch {
    err =>
      raise KgfManageError::InstallError(
        "Failed to create directory: " + err.to_string(),
      )
  }
  @platform.write_bytes_async(dst_path, content) catch {
    err =>
      raise KgfManageError::InstallError(
        "Failed to write spec file: " + err.to_string(),
      )
  }
  println("Installed " + relative_path + " to " + dst_path)
}
