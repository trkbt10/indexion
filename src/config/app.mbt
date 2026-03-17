///|
/// indexion application constants and directory resolution.
/// Application-specific knowledge that depends on platform detection.

///|
/// Resolve an OS-standard directory for indexion.
/// Single source of truth for platform-specific directory resolution.
///
/// Parameters:
/// - macos_subpath: path under ~/Library/ (e.g., "Application Support/Indexion")
/// - xdg_env: XDG environment variable name (e.g., "XDG_CONFIG_HOME")
/// - linux_fallback: fallback under $HOME (e.g., ".config/indexion")
/// - windows_env: Windows environment variable (e.g., "APPDATA")
/// - windows_subpath: subpath under the Windows env dir (e.g., "/Indexion")
fn resolve_os_dir(
  macos_subpath : String,
  xdg_env : String,
  linux_fallback : String,
  windows_env : String,
  windows_subpath : String,
) -> String? {
  match @platform.detect_platform() {
    MacOS =>
      match @platform.get_home_dir() {
        Some(home) => Some(home + "/Library/" + macos_subpath)
        None => None
      }
    Linux => {
      match @sys.get_env_var(xdg_env) {
        Some(xdg) => if xdg.length() > 0 { return Some(xdg + "/indexion") }
        None => ()
      }
      match @platform.get_home_dir() {
        Some(home) => Some(home + "/" + linux_fallback)
        None => None
      }
    }
    Windows =>
      match @sys.get_env_var(windows_env) {
        Some(dir) =>
          if dir.length() > 0 {
            Some(dir + windows_subpath)
          } else {
            None
          }
        None => None
      }
    Unknown =>
      match @platform.get_home_dir() {
        Some(home) => Some(home + "/" + linux_fallback)
        None => None
      }
  }
}

///|
/// Get OS-standard configuration directory for indexion.
pub fn get_global_config_dir() -> String? {
  resolve_os_dir(
    "Application Support/Indexion", "XDG_CONFIG_HOME", ".config/indexion", "APPDATA",
    "/Indexion",
  )
}

///|
/// Get OS-standard data directory for indexion.
pub fn get_global_data_dir() -> String? {
  resolve_os_dir(
    "Application Support/Indexion", "XDG_DATA_HOME", ".local/share/indexion", "LOCALAPPDATA",
    "/Indexion",
  )
}

///|
/// Get OS-standard cache directory for indexion.
pub fn get_global_cache_dir() -> String? {
  resolve_os_dir(
    "Caches/Indexion", "XDG_CACHE_HOME", ".cache/indexion", "LOCALAPPDATA", "/Indexion/Cache",
  )
}

///|
/// Get the indexion install directory.
/// Priority: INDEXION_INSTALL_DIR env var, then ~/.indexion
/// This is the SoT for install directory resolution.
pub fn get_install_dir() -> String? {
  match @sys.get_env_var("INDEXION_INSTALL_DIR") {
    Some(dir) => if dir.length() > 0 { return Some(dir) }
    None => ()
  }
  match @platform.get_home_dir() {
    Some(home) => Some(home + "/.indexion")
    None => None
  }
}

///|
/// Get the platform asset name for release downloads.
/// Maps Platform + Arch to the asset naming convention used in GitHub Releases.
/// This is the SoT for platform-to-asset mapping.
pub fn get_platform_asset_name() -> String? {
  let arch = @platform.detect_arch()
  let arch_str = match arch {
    X64 => "x64"
    Arm64 => "arm64"
    UnknownArch => return None
  }
  match @platform.detect_platform() {
    MacOS => Some("indexion-darwin-" + arch_str)
    Linux => Some("indexion-linux-" + arch_str)
    Windows => Some("indexion-windows-" + arch_str)
    Unknown => None
  }
}

///|
/// Get the archive extension for the current platform.
pub fn get_archive_extension() -> String {
  match @platform.detect_platform() {
    Windows => ".zip"
    _ => ".tar.gz"
  }
}

///|
/// Get the binary name for the current platform.
pub fn get_binary_name() -> String {
  match @platform.detect_platform() {
    Windows => "indexion.exe"
    _ => "indexion"
  }
}
