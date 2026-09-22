///|
/// Resolve the installed kgfs directory using the config SoT.
pub fn get_installed_kgfs_dir() -> String? {
  @config.find_kgfs_dir()
}

///|
/// List all installed specs with metadata.
/// Category is derived from the subdirectory name (not hardcoded).
pub fn list_installed_specs() -> Array[KgfSpecInfo] {
  let kgfs_dir = match get_installed_kgfs_dir() {
    Some(dir) => dir
    None => return []
  }
  list_specs_from_dir(kgfs_dir)
}

///|
/// List specs from a resolved kgfs directory.
pub fn list_specs_from_dir(kgfs_dir : String) -> Array[KgfSpecInfo] {
  let specs : Array[KgfSpecInfo] = []
  collect_specs_recursive(kgfs_dir, kgfs_dir, specs)
  sort_specs(specs)
  specs
}

///|
/// List the specs of a layered spec set, resolved the way the registry
/// resolves them: directories are walked in order, and a spec whose language
/// name repeats replaces the earlier one.
///
/// This is the listing counterpart of `KGFRegistry::load_from_dirs`, and the
/// SoT for reporting which file won for a language. Within one directory the
/// last file wins, matching the registry's sorted traversal.
pub fn list_specs_from_dirs(dirs : Array[String]) -> Array[KgfResolvedSpec] {
  let by_name : Map[String, KgfResolvedSpec] = Map([])
  for layer, dir in dirs {
    for info in list_specs_from_dir(dir) {
      let shadowed : Array[String] = []
      match by_name.get(info.name) {
        Some(previous) => {
          for path in previous.shadowed {
            shadowed.push(path)
          }
          shadowed.push(previous.info.path)
        }
        None => ()
      }
      by_name.set(info.name, { info, layer, shadowed, })
    }
  }
  let resolved : Array[KgfResolvedSpec] = []
  for entry in by_name {
    resolved.push(entry.1)
  }
  sort_resolved_specs(resolved)
  resolved
}

///|
/// Sort resolved specs by category then name, matching `sort_specs`.
fn sort_resolved_specs(specs : Array[KgfResolvedSpec]) -> Unit {
  for i = 0; i < specs.length(); i = i + 1 {
    for j = i + 1; j < specs.length(); j = j + 1 {
      let swap = if specs[j].info.category < specs[i].info.category {
        true
      } else if specs[j].info.category == specs[i].info.category &&
        specs[j].info.name < specs[i].info.name {
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

///|
/// Recursively scan directory for .kgf files and extract metadata.
fn collect_specs_recursive(
  dir : String,
  root_dir : String,
  specs : Array[KgfSpecInfo],
) -> Unit {
  try {
    if !@fs.is_dir(dir) {
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
      } else if @fs.is_dir(path) && !entry.has_prefix(".") {
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
    Some({
      name,
      category,
      sources: header.sources,
      path,
      extends: header.get_extends(),
    })
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
