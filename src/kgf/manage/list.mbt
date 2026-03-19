///|
/// Resolve the installed kgfs directory using the config SoT.
pub fn get_installed_kgfs_dir() -> String? {
  @config.find_kgfs_dir()
}

///|
/// List all installed specs with metadata.
/// Category is derived from the subdirectory name (not hardcoded).
pub fn list_installed_specs() -> Array[KgfSpecInfo] {
  let specs : Array[KgfSpecInfo] = []
  let kgfs_dir = match get_installed_kgfs_dir() {
    Some(dir) => dir
    None => return specs
  }
  collect_specs_recursive(kgfs_dir, kgfs_dir, specs)
  sort_specs(specs)
  specs
}

///|
/// Recursively scan directory for .kgf files and extract metadata.
fn collect_specs_recursive(
  dir : String,
  root_dir : String,
  specs : Array[KgfSpecInfo],
) -> Unit {
  try {
    if not(@fs.is_dir(dir)) {
      return
    }
    let entries = @fs.read_dir(dir)
    for entry in entries {
      let path = dir + "/" + entry
      if entry.has_suffix(".kgf") {
        match extract_spec_info(path, root_dir) {
          Some(info) => specs.push(info)
          None => ()
        }
      } else if @fs.is_dir(path) && not(entry.has_prefix(".")) {
        collect_specs_recursive(path, root_dir, specs)
      }
    }
  } catch {
    _ => ()
  }
}

///|
/// Extract spec metadata from a .kgf file using header-only parse.
fn extract_spec_info(path : String, root_dir : String) -> KgfSpecInfo? {
  try {
    let content = @fs.read_file_to_string(path)
    let header = @parser.parse_kgf_header(content)
    let name = header.language
    if name.length() == 0 {
      return None
    }
    let category = derive_category(path, root_dir)
    Some({ name, category, sources: header.sources, path })
  } catch {
    _ => None
  }
}

///|
/// Derive category from relative path between file and kgfs root.
/// e.g., root="/data/kgfs", path="/data/kgfs/programming/go.kgf" → "programming"
fn derive_category(path : String, root_dir : String) -> String {
  let rel = if path.length() > root_dir.length() + 1 {
    let start = root_dir.length() + 1
    let chars = path.to_array()
    let result : Array[Char] = []
    for i = start; i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    return ""
  }
  // Category is the first path segment (before first '/')
  let chars = rel.to_array()
  let result : Array[Char] = []
  for c in chars {
    if c == '/' {
      break
    }
    result.push(c)
  }
  let first_segment = String::from_array(result)
  // If the first segment ends with .kgf, it's a root-level file (no category)
  if first_segment.has_suffix(".kgf") {
    ""
  } else {
    first_segment
  }
}

///|
/// Sort specs by category then name.
fn sort_specs(specs : Array[KgfSpecInfo]) -> Unit {
  for i = 0; i < specs.length(); i = i + 1 {
    for j = i + 1; j < specs.length(); j = j + 1 {
      let swap = if specs[j].category < specs[i].category {
        true
      } else if specs[j].category == specs[i].category &&
        specs[j].name < specs[i].name {
        true
      } else {
        false
      }
      if swap {
        let tmp = specs[i]
        specs[i] = specs[j]
        specs[j] = tmp
      }
    }
  }
}
