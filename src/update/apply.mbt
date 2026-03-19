///|
/// Error type for update operations.

///|
pub suberror UpdateError {
  NetworkError(String)
  ApiError(String)
  ParseError(String)
  PlatformError(String)
  DownloadError(String)
  ChecksumError(String)
  InstallError(String)
}

///|
pub fn UpdateError::to_string(self : UpdateError) -> String {
  match self {
    NetworkError(msg) => "network error: " + msg
    ApiError(msg) => "API error: " + msg
    ParseError(msg) => "parse error: " + msg
    PlatformError(msg) => "platform error: " + msg
    DownloadError(msg) => "download error: " + msg
    ChecksumError(msg) => "checksum error: " + msg
    InstallError(msg) => "install error: " + msg
  }
}

///|
/// Get the install directory for indexion, delegating to config SoT.
pub fn get_install_dir() -> String raise UpdateError {
  match @config.get_install_dir() {
    Some(dir) => dir
    None =>
      raise UpdateError::InstallError("Cannot determine install directory")
  }
}

///|
/// Perform the full update: download, verify, extract, and install.
/// File operations use @platform.* native async APIs.
/// Shell dependency is limited to archive extraction via @platform.extract_archive.
pub async fn perform_update(version : String) -> Unit raise UpdateError {
  let asset = get_platform_asset()
  let install_dir = get_install_dir()
  let bin_dir = @config.join_path(install_dir, "bin")
  let archive_ext = @config.get_archive_extension()
  // Download archive and checksum
  println("Downloading " + asset + archive_ext + "...")
  let download_url = build_download_url(version, asset)
  let checksum_url = build_checksum_url(version, asset)
  let archive_data = download_bytes(download_url)
  println("Verifying checksum...")
  let checksum_text = download_text(checksum_url)
  verify_checksum(archive_data, checksum_text)
  println("Checksum OK")
  // Temp workspace
  let tmp_dir = @platform.create_temp_dir("indexion-update") catch {
    err =>
      raise UpdateError::InstallError(
        "Failed to create temp directory: " + err.to_string(),
      )
  }
  let archive_path = @config.join_path(tmp_dir, "archive" + archive_ext)
  // Write archive
  @platform.write_bytes_async(archive_path, archive_data) catch {
    err =>
      raise UpdateError::InstallError(
        "Failed to write archive to " + archive_path + ": " + err.to_string(),
      )
  }
  // Extract
  println("Extracting...")
  @platform.extract_archive(archive_path, tmp_dir) catch {
    err =>
      raise UpdateError::InstallError(
        "Failed to extract archive: " + err.to_string(),
      )
  }
  // Install binary
  let binary_name = @config.get_binary_name()
  let extracted_dir = @config.join_path(tmp_dir, asset)
  let src_binary = @config.join_path(extracted_dir, binary_name)
  let dst_binary = @config.join_path(bin_dir, binary_name)
  @platform.ensure_dir_async(bin_dir) catch {
    err =>
      raise UpdateError::InstallError(
        "Failed to create bin directory: " + err.to_string(),
      )
  }
  println("Installing to " + dst_binary + "...")
  @platform.install_binary(src_binary, dst_binary) catch {
    err =>
      raise UpdateError::InstallError(
        "Failed to install binary: " + err.to_string(),
      )
  }
  @platform.make_executable(dst_binary) catch {
    err =>
      raise UpdateError::InstallError(
        "Failed to set executable permission: " + err.to_string(),
      )
  }
  // Install kgfs to OS-standard data directory (delegated to kgf manage SoT)
  let src_kgfs = @config.join_path(extracted_dir, "kgfs")
  let kgfs_exists = @platform.path_exists_async(src_kgfs) catch { _ => false }
  if kgfs_exists {
    @kgf_manage.install_kgfs_from_dir(src_kgfs) catch {
      err =>
        raise UpdateError::InstallError(
          "Failed to install kgfs: " + err.to_string(),
        )
    }
  }
  // Cleanup
  @platform.remove_dir_recursive(tmp_dir) catch {
    _ => ()
  }
  println("Updated to " + version)
}
