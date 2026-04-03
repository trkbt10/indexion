///|
/// Documentation analysis - extract doc coverage from MoonBit files.

///|
/// Project info from moon.mod.json.
pub struct ProjectInfo {
  name : String
  version : String
  description : String
  repository : String
  license : String
  keywords : Array[String]
}

///|
pub fn ProjectInfo::default() -> ProjectInfo {
  {
    name: "project",
    version: "0.0.0",
    description: "",
    repository: "",
    license: "",
    keywords: [],
  }
}

///|
/// A public item (function, type, etc.) found in the code.
pub struct PubItem {
  name : String
  kind : String // "fn", "type", "struct", "enum", "trait"
  kind_category : String // "function" or "type", from KGF function_kinds feature
  file : String
  line : Int
  has_doc : Bool
  doc_preview : String // first line of doc if exists
}

///|
/// Package-level documentation analysis.
pub struct PackageAnalysis {
  path : String
  files : Array[String]
  pub_items : Array[PubItem]
  total_pub : Int
  documented : Int
  has_readme : Bool
}

///|
/// Full documentation analysis result.
pub struct DocAnalysis {
  packages : Array[PackageAnalysis]
  total_pub_items : Int
  total_documented : Int
  coverage_percent : Double
  critical_missing : Array[PubItem] // high priority undocumented
}

///|
/// Load project info from moon.mod.json.
pub fn load_project_info(dir : String) -> ProjectInfo {
  let path = @common.normalize_path(dir) + "/moon.mod.json"
  try {
    let content = @fs.read_file_to_string(path)
    parse_moon_mod_json(content)
  } catch {
    _ => ProjectInfo::default()
  }
}

///|
fn parse_moon_mod_json(content : String) -> ProjectInfo {
  let mut info = ProjectInfo::default()
  // Simple JSON parsing for specific fields
  info = { ..info, name: @common.extract_json_string(content, "name") }
  info = { ..info, version: @common.extract_json_string(content, "version") }
  info = {
    ..info,
    description: @common.extract_json_string(content, "description"),
  }
  info = {
    ..info,
    repository: @common.extract_json_string(content, "repository"),
  }
  info = { ..info, license: @common.extract_json_string(content, "license") }
  info = { ..info, keywords: @common.extract_json_array(content, "keywords") }
  info
}

// extract_json_string, extract_json_array: use @common (SoT)

///|
/// Analyze documentation coverage in directory.
/// Uses @pipeline.discover_files (SoT) for file collection, then groups
/// files by directory — the same approach as doc readme's
/// discover_packages_from_files.
pub fn analyze_documentation(
  dir : String,
  specs_dir? : String = "kgfs",
) -> DocAnalysis {
  let all_items : Array[PubItem] = []
  let normalized_dir = @common.normalize_path(dir)
  let registry = @kgf_features.load_registry(
    specs_dir~,
    target_dir=normalized_dir,
  )
  // Collect KGF ignore patterns for discover_files
  let kgf_ignore : Array[(String, String)] = match registry {
    Some(reg) => reg.collect_ignore_patterns()
    None => []
  }
  // Stage 1: Discover files using pipeline SoT
  let discover_opts = @pipeline.DiscoverOptions::new(
    recursive=true,
    kgf_ignore~,
  )
  let file_paths = @pipeline.discover_files([normalized_dir], discover_opts)
  // Stage 2: Filter to KGF-supported files and group by directory
  let by_dir : Map[String, Array[String]] = {}
  for path in file_paths {
    let supported = match registry {
      Some(reg) => reg.is_file_supported(path)
      None => false
    }
    if supported {
      let dir_path = @common.parent_dir(path)
      match by_dir.get(dir_path) {
        Some(arr) => arr.push(path)
        None => by_dir.set(dir_path, [path])
      }
    }
  }
  // Stage 3: Analyze each directory group as a package
  let packages : Array[PackageAnalysis] = []
  for entry in by_dir {
    let pkg_dir = entry.0
    let files = entry.1
    let rel_path = @common.make_relative_path(pkg_dir, normalized_dir)
    let pkg_path = if rel_path.length() > 0 { rel_path } else { "." }
    // Check README presence
    let has_readme = dir_has_readme(pkg_dir)
    // Analyze source files
    let pub_items : Array[PubItem] = []
    for file_path in files {
      let file_rel = @common.make_relative_path(file_path, normalized_dir)
      analyze_source_file(file_path, file_rel, pub_items, registry)
    }
    let documented = pub_items
      .iter()
      .filter(fn(i) { i.has_doc })
      .fold(init=0, fn(acc, _) { acc + 1 })
    let file_names = files.map(fn(f) { @config.basename(f) })
    packages.push({
      path: pkg_path,
      files: file_names,
      pub_items,
      total_pub: pub_items.length(),
      documented,
      has_readme,
    })
  }
  // Aggregate stats
  let mut total_pub = 0
  let mut total_doc = 0
  for pkg in packages {
    total_pub = total_pub + pkg.total_pub
    total_doc = total_doc + pkg.documented
    for item in pkg.pub_items {
      all_items.push(item)
    }
  }
  let coverage = if total_pub > 0 {
    total_doc.to_double() / total_pub.to_double() * 100.0
  } else {
    100.0
  }
  // Find critical missing (pub fn/type without docs)
  let critical : Array[PubItem] = []
  for item in all_items {
    if !item.has_doc {
      critical.push(item)
    }
  }
  // Sort critical by file
  sort_pub_items(critical)
  {
    packages,
    total_pub_items: total_pub,
    total_documented: total_doc,
    coverage_percent: coverage,
    critical_missing: critical,
  }
}

///|
/// Check if a directory contains a README file.
fn dir_has_readme(dir : String) -> Bool {
  try {
    let entries = @fs.read_dir(dir)
    for entry in entries {
      if entry.has_prefix("README") {
        return true
      }
    }
    false
  } catch {
    _ => false
  }
}

///|
/// Analyze source file for public declarations using KGF tokenization.
/// Associates doc comments with declarations via single-pass KGF token extraction.
fn analyze_source_file(
  path : String,
  rel_path : String,
  items : Array[PubItem],
  registry : @kgf_registry.KGFRegistry?,
) -> Unit {
  try {
    let content = @fs.read_file_to_string(path)
    // Extract both declarations and doc map in a single tokenization pass
    let (declarations, doc_map) = @kgf_features.extract_pub_declarations_and_doc_map(
      content, path, registry,
    )
    if declarations.length() == 0 {
      return
    }
    // Associate declarations with their doc comments
    for decl in declarations {
      let doc_lines = match doc_map.get(decl.line) {
        Some(doc) => @common.split_lines(doc)
        None => []
      }
      items.push(make_pub_item(decl, rel_path, doc_lines))
    }
  } catch {
    _ => ()
  }
}

///|
fn make_pub_item(
  decl : @kgf_features.PubDeclaration,
  file : String,
  doc_lines : Array[String],
) -> PubItem {
  let has_doc = doc_lines.length() > 0
  let doc_preview = if has_doc && doc_lines[0].length() > 0 {
    let preview = doc_lines[0]
    if preview.length() > 60 {
      @common.substring(preview, 0, 60) + "..."
    } else {
      preview
    }
  } else {
    ""
  }
  {
    name: decl.name,
    kind: decl.kind,
    kind_category: decl.category,
    file,
    line: decl.line,
    has_doc,
    doc_preview,
  }
}

// extract_identifier, is_ident_char: no longer needed (KGF handles identification)
// use @common (SoT) — split_lines

// use @common (SoT) — trim_ascii_spaces, substring, normalize_path

///|
fn sort_pub_items(items : Array[PubItem]) -> Unit {
  items.sort_by(fn(a, b) {
    let cmp = a.file.compare(b.file)
    if cmp != 0 {
      cmp
    } else {
      a.line.compare(b.line)
    }
  })
}
