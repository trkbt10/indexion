///|
/// Path resolution for indexion configuration.
/// This is the Single Source of Truth for finding kgfs directory.

///|
/// Find kgfs directory.
/// Priority:
/// 1. Explicit path (--kgfs-dir CLI option)
/// 2. INDEXION_KGFS_DIR environment variable
/// 3. ~/.indexion/kgfs (user local - for binary distribution)
/// 4. kgfs/ relative to CWD (development - submodule)
pub fn find_kgfs_dir(explicit_path? : String = "") -> String? {
  // 1. Explicit override (from CLI option)
  if explicit_path.length() > 0 && is_valid_dir(explicit_path) {
    return Some(explicit_path)
  }
  // 2. INDEXION_KGFS_DIR environment variable
  match @sys.get_env_var("INDEXION_KGFS_DIR") {
    Some(dir) => if dir.length() > 0 && is_valid_dir(dir) { return Some(dir) }
    None => ()
  }
  // 3. ~/.indexion/kgfs (user local installation)
  match get_home_dir() {
    Some(home) => {
      let kgfs_path = home + "/.indexion/kgfs"
      if is_valid_dir(kgfs_path) {
        return Some(kgfs_path)
      }
    }
    None => ()
  }
  // 4. kgfs/ relative to CWD (development with submodule)
  if is_valid_dir("kgfs") {
    return Some("kgfs")
  }
  None
}

///|
/// Get user home directory.
pub fn get_home_dir() -> String? {
  // Try HOME (Unix) then USERPROFILE (Windows)
  match @sys.get_env_var("HOME") {
    Some(h) => if h.length() > 0 { return Some(h) }
    None => ()
  }
  match @sys.get_env_var("USERPROFILE") {
    Some(h) => if h.length() > 0 { return Some(h) }
    None => ()
  }
  None
}

///|
/// Check if a path is a valid directory.
fn is_valid_dir(path : String) -> Bool {
  @fs.is_dir(path) catch {
    _ => false
  }
}
