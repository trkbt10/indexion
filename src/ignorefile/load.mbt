///|
/// Load and parse a gitignore-syntax file from a directory.
/// SoT for all ignore file reading.
pub fn load_from_dir(dir : String, filename : String) -> Array[IgnorePattern] {
  let path = dir + "/" + filename
  try {
    let content = @fs.read_file_to_string(path)
    parse(content, path)
  } catch {
    _ => []
  }
}
