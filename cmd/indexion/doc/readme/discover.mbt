///|
/// Information about a discovered package.
pub struct PackageInfo {
  path : String
  name : String
  main_file : String?
}

///|
pub fn PackageInfo::new(path : String, name : String) -> PackageInfo {
  let main_file = find_main_source(path)
  { path, name, main_file }
}

///|
/// Discover packages from given paths with include/exclude filtering.
pub fn discover_packages(
  paths : Array[String],
  includes : Array[String],
  excludes : Array[String],
  recursive : Bool,
) -> Array[PackageInfo] {
  let packages : Array[PackageInfo] = []
  for path in paths {
    let clean_path = trim_trailing_slash(path)
    discover_packages_impl(clean_path, includes, excludes, recursive, packages)
  }
  packages
}

///|
fn discover_packages_impl(
  path : String,
  includes : Array[String],
  excludes : Array[String],
  recursive : Bool,
  packages : Array[PackageInfo],
) -> Unit {
  try {
    if not(@fs.is_dir(path)) {
      return
    }
    // Check if this is a package (has .mbt files)
    if is_moonbit_package(path) {
      let name = extract_package_name(path)
      if should_include_package(name, includes, excludes) {
        packages.push(PackageInfo::new(path, name))
      }
    }
    // Recurse into subdirectories
    if recursive {
      let entries = @fs.read_dir(path)
      for entry in entries {
        // Skip hidden directories and common non-package directories
        if entry.has_prefix(".") || entry == "node_modules" || entry == "target" {
          continue
        }
        let subpath = path + "/" + entry
        if @fs.is_dir(subpath) {
          discover_packages_impl(
            subpath, includes, excludes, recursive, packages,
          )
        }
      }
    }
  } catch {
    _ => ()
  }
}

///|
/// Check if directory is a MoonBit package (contains .mbt files).
fn is_moonbit_package(dir : String) -> Bool {
  try {
    let entries = @fs.read_dir(dir)
    for entry in entries {
      if entry.has_suffix(".mbt") && not(entry.has_suffix("_wbtest.mbt")) {
        return true
      }
    }
    false
  } catch {
    _ => false
  }
}

///|
/// Extract package name from path.
fn extract_package_name(path : String) -> String {
  let chars = path.to_array()
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last_slash = i
    }
  }
  if last_slash >= 0 && last_slash < chars.length() - 1 {
    let result : Array[Char] = []
    for i = last_slash + 1; i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    path
  }
}

///|
fn trim_trailing_slash(path : String) -> String {
  if path.length() > 0 && path.has_suffix("/") {
    let chars = path.to_array()
    let result : Array[Char] = []
    for i = 0; i < chars.length() - 1; i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    path
  }
}

///|
/// Check if package should be included based on include/exclude patterns.
fn should_include_package(
  name : String,
  includes : Array[String],
  excludes : Array[String],
) -> Bool {
  // Check excludes first
  for pattern in excludes {
    if matches_pattern(name, pattern) {
      return false
    }
  }
  // If no includes specified, include all (that weren't excluded)
  if includes.length() == 0 {
    return true
  }
  // Check includes
  for pattern in includes {
    if matches_pattern(name, pattern) {
      return true
    }
  }
  false
}

///|
/// Check if string matches a glob pattern (simple implementation).
/// Supports * wildcard.
pub fn matches_pattern(text : String, pattern : String) -> Bool {
  let text_chars = text.to_array()
  let pat_chars = pattern.to_array()
  matches_pattern_impl(text_chars, 0, pat_chars, 0)
}

///|
fn matches_pattern_impl(
  text : Array[Char],
  ti : Int,
  pat : Array[Char],
  pi : Int,
) -> Bool {
  // Both exhausted
  if ti >= text.length() && pi >= pat.length() {
    return true
  }
  // Pattern exhausted but text remains
  if pi >= pat.length() {
    return false
  }
  // Handle wildcard
  if pat[pi] == '*' {
    // Try matching zero or more characters
    // First, try skipping the wildcard (match zero chars)
    if matches_pattern_impl(text, ti, pat, pi + 1) {
      return true
    }
    // Then try consuming one char from text
    if ti < text.length() {
      return matches_pattern_impl(text, ti + 1, pat, pi)
    }
    return false
  }
  // Text exhausted but pattern remains (non-wildcard)
  if ti >= text.length() {
    return false
  }
  // Match single character
  if pat[pi] == text[ti] {
    return matches_pattern_impl(text, ti + 1, pat, pi + 1)
  }
  false
}
