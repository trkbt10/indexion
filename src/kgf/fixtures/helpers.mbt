///|
/// Common helpers for fixture tests.

///|
/// Find the fixtures directory by walking up from the test execution directory.
/// Returns None if not found (e.g. CI where cwd is deep in _build/).
pub fn find_fixtures_dir() -> String? {
  let paths = [
    "fixtures", "../fixtures", "../../fixtures", "../../../fixtures", "../../../../fixtures",
    "../../../../../fixtures",
  ]
  for path in paths {
    try {
      if @fs.is_dir(path) {
        return Some(path)
      }
    } catch {
      _ => continue
    }
  }
  None
}

///|
/// Find the kgfs directory by walking up from the test execution directory.
/// Returns None if not found.
pub fn find_kgfs_dir() -> String? {
  let paths = [
    "kgfs", "../kgfs", "../../kgfs", "../../../kgfs", "../../../../kgfs", "../../../../../kgfs",
  ]
  for path in paths {
    try {
      if @fs.is_dir(path) {
        return Some(path)
      }
    } catch {
      _ => continue
    }
  }
  None
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
