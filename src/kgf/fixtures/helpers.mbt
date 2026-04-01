///|
/// Common helpers for fixture tests.

///|
/// Walk up from "." looking for a directory named `name`.
/// Stops at filesystem root or on permission error.
fn find_ancestor_dir(name : String) -> String? {
  let mut prefix = ""
  // Limit to prevent infinite loop, but the real stop is dirname convergence
  for i = 0; i < 64; i = i + 1 {
    let candidate = if prefix.length() == 0 { name } else { prefix + name }
    let exists = try {
      @fs.is_dir(candidate)
    } catch {
      // Permission error or other OS error — stop walking
      _ => return None
    }
    if exists {
      return Some(candidate)
    }
    // Check if we've reached the root (prefix didn't grow)
    let parent = prefix + ".."
    let can_access = try {
      @fs.is_dir(parent)
    } catch {
      _ => return None
    }
    if !can_access {
      return None
    }
    prefix = parent + "/"
  }
  None
}

///|
/// Find the fixtures directory by walking up from cwd.
/// Returns None if not reachable.
pub fn find_fixtures_dir() -> String? {
  find_ancestor_dir("fixtures")
}

///|
/// Find the kgfs directory by walking up from cwd.
/// Returns None if not reachable.
pub fn find_kgfs_dir() -> String? {
  find_ancestor_dir("kgfs")
}

///|
/// Find the fixtures directory, falling back to "fixtures" if not found.
pub fn get_fixtures_dir() -> String {
  find_fixtures_dir().unwrap_or("fixtures")
}

///|
/// Find the kgfs directory, falling back to "kgfs" if not found.
pub fn get_kgfs_dir() -> String {
  find_kgfs_dir().unwrap_or("kgfs")
}
