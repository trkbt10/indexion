///|
/// Package discovery using KGF registry for language detection.

///|
/// Information about a discovered package.
pub struct PackageInfo {
  path : String
  name : String
  files : Array[String]
}

///|
/// Create a new package info with path, name, and file list.
pub fn PackageInfo::new(
  path : String,
  name : String,
  files : Array[String],
) -> PackageInfo {
  { path, name, files }
}

///|
/// Discover packages from given paths using KGF registry.
pub fn discover_packages(
  registry : @registry.KGFRegistry,
  paths : Array[String],
  includes : Array[String],
  excludes : Array[String],
  recursive : Bool,
) -> Array[PackageInfo] {
  let packages : Array[PackageInfo] = []
  // Build filter config with user patterns
  let filter = @filter.FilterConfig::new()
    .with_includes(includes)
    .with_excludes(excludes)
  for path in paths {
    let clean_path = @pipeline.trim_trailing_slash(path)
    discover_impl(registry, clean_path, filter, recursive, packages)
  }
  packages
}

///|
/// Discover packages from a pre-collected file path list.
pub fn discover_packages_from_files(
  registry : @registry.KGFRegistry,
  file_paths : Array[String],
  includes : Array[String],
  excludes : Array[String],
) -> Array[PackageInfo] {
  let filter = @filter.FilterConfig::new()
    .with_includes(includes)
    .with_excludes(excludes)
  let by_dir : Map[String, Array[String]] = {}
  for path in file_paths {
    if registry.is_file_supported(path) {
      let dir = extract_parent_dir(path)
      match by_dir.get(dir) {
        Some(arr) => arr.push(path)
        None => by_dir.set(dir, [path])
      }
    }
  }
  let packages : Array[PackageInfo] = []
  for entry in by_dir {
    let dir = entry.0
    let files = entry.1
    if files.length() == 0 ||
      not(filter.should_include(dir, true).is_included()) {
      continue
    }
    let name = extract_dir_name(dir)
    packages.push(PackageInfo::new(dir, name, files))
  }
  packages
}

///|
fn discover_impl(
  registry : @registry.KGFRegistry,
  path : String,
  filter : @filter.FilterConfig,
  recursive : Bool,
  packages : Array[PackageInfo],
) -> Unit {
  try {
    if not(@fs.is_dir(path)) {
      return
    }
    // Check if path should be included
    if not(filter.should_include(path, true).is_included()) {
      return
    }
    // Collect supported files in this directory
    let files = collect_supported_files(registry, path)
    if files.length() > 0 {
      let name = extract_dir_name(path)
      packages.push(PackageInfo::new(path, name, files))
    }
    // Recurse into subdirectories
    if recursive {
      let entries = @fs.read_dir(path)
      for entry in entries {
        if filter.should_skip_dir(entry) {
          continue
        }
        let subpath = path + "/" + entry
        if @fs.is_dir(subpath) {
          discover_impl(registry, subpath, filter, recursive, packages)
        }
      }
    }
  } catch {
    _ => ()
  }
}

///|
/// Collect files supported by KGF registry in a directory.
fn collect_supported_files(
  registry : @registry.KGFRegistry,
  dir : String,
) -> Array[String] {
  let files : Array[String] = []
  try {
    let entries = @fs.read_dir(dir)
    for entry in entries {
      let path = dir + "/" + entry
      if @fs.is_file(path) && registry.is_file_supported(path) {
        files.push(path)
      }
    }
  } catch {
    _ => ()
  }
  files
}

///|
fn extract_parent_dir(path : String) -> String {
  let chars = path.to_array()
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' || chars[i] == '\\' {
      last_slash = i
    }
  }
  if last_slash > 0 {
    let result : Array[Char] = []
    for i = 0; i < last_slash; i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    "."
  }
}

///|
/// Extract directory name from path.
fn extract_dir_name(path : String) -> String {
  @pipeline.extract_basename(path)
}
