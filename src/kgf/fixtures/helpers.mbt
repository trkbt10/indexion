///|
/// Common helpers for fixture tests.

///|
pub fn get_fixtures_dir() -> String {
  let paths = ["fixtures", "../fixtures", "../../fixtures", "../../../fixtures", "../../../../fixtures", "../../../../../fixtures"]
  for path in paths {
    try { if @fs.is_dir(path) { return path } } catch { _ => continue }
  }
  "fixtures"
}

///|
pub fn get_kgfs_dir() -> String {
  let paths = ["kgfs", "../kgfs", "../../kgfs", "../../../kgfs", "../../../../kgfs", "../../../../../kgfs"]
  for path in paths {
    try { if @fs.is_dir(path) { return path } } catch { _ => continue }
  }
  "kgfs"
}
