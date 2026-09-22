///|
/// OKF bundle construction: turns analyzed package concepts into a complete
/// Open Knowledge Format bundle as `(relative_path, content)` pairs.
///
/// Layout:
///   index.md                      (root listing)
///   log.md                        (generation history; only with timestamp)
///   packages/<pkg path>.md        (one concept per analyzed package)
///   dependencies/<import path>.md (one concept per external dependency)
/// plus an `index.md` in every intermediate directory so consumers can
/// discover the bundle progressively, as recommended by the OKF spec.

///|
/// Internal record of an emitted concept, used to build index listings.
priv struct ConceptEntry {
  path : String
  title : String
  description : String
  concept_type : String
}

///|
/// Build a complete OKF bundle from package concepts.
/// Returns `(bundle-relative path, file content)` pairs in deterministic
/// order: package concepts, dependency concepts, index files, then log.
pub fn build_bundle(
  packages : Array[OkfPackageConcept],
  options : OkfBundleOptions,
) -> Array[(String, String)] {
  let sorted = packages.copy()
  sorted.sort_by(fn(a, b) {
    normalize_package_path(a.path).compare(normalize_package_path(b.path))
  })
  // Reverse dependency maps keyed by normalized target.
  let internal_dependents : Map[String, Array[String]] = Map([])
  let external_dependents : Map[String, Array[String]] = Map([])
  let known_packages : Map[String, Bool] = Map([])
  for pkg in sorted {
    known_packages.set(normalize_package_path(pkg.path), true)
  }
  for pkg in sorted {
    let from = normalize_package_path(pkg.path)
    for dep in pkg.depends_on {
      if dep.internal {
        let target = normalize_package_path(dep.target)
        if !known_packages.contains(target) {
          continue
        }
        match internal_dependents.get(target) {
          Some(arr) => if !arr.contains(from) { arr.push(from) }
          None => internal_dependents.set(target, [from])
        }
      } else {
        let target = sanitize_bundle_path(dep.target)
        match external_dependents.get(target) {
          Some(arr) => if !arr.contains(from) { arr.push(from) }
          None => external_dependents.set(target, [from])
        }
      }
    }
  }
  // Allocate collision-free concept file paths up front so that concept
  // emission and cross-links agree, and so that a package or dependency
  // whose final segment is a reserved OKF filename (`index`, `log`) cannot
  // be clobbered by a directory listing.
  let external_targets : Array[String] = []
  for entry in external_dependents {
    external_targets.push(entry.0)
  }
  external_targets.sort()
  let taken : Map[String, Bool] = Map([])
  let package_concept_paths : Map[String, String] = Map([])
  for pkg in sorted {
    let norm = normalize_package_path(pkg.path)
    if package_concept_paths.contains(norm) {
      continue
    }
    let concept_path = allocate_concept_path(taken, OKF_PACKAGES_DIR, norm)
    package_concept_paths.set(norm, concept_path)
  }
  let external_concept_paths : Map[String, String] = Map([])
  for target in external_targets {
    let concept_path = allocate_concept_path(
      taken,
      OKF_DEPENDENCIES_DIR,
      target,
    )
    external_concept_paths.set(target, concept_path)
  }
  let files : Array[(String, String)] = []
  let entries : Array[ConceptEntry] = []
  let emitted : Map[String, Bool] = Map([])
  // Package concepts.
  for pkg in sorted {
    let norm = normalize_package_path(pkg.path)
    if emitted.contains(norm) {
      continue
    }
    emitted.set(norm, true)
    guard package_concept_paths.get(norm) is Some(concept_path) else {
      continue
    }
    let dependents = sorted_or_empty(internal_dependents.get(norm))
    files.push(
      (
        concept_path,
        render_package_concept(
          pkg, dependents, options, package_concept_paths, external_concept_paths,
        ),
      ),
    )
    entries.push({
      path: concept_path,
      title: norm,
      description: pkg.description,
      concept_type: OKF_TYPE_PACKAGE,
    })
  }
  // External dependency concepts.
  for target in external_targets {
    guard external_concept_paths.get(target) is Some(concept_path) else {
      continue
    }
    let dependents = sorted_or_empty(external_dependents.get(target))
    files.push(
      (
        concept_path,
        render_external_concept(
          target, dependents, options, package_concept_paths,
        ),
      ),
    )
    entries.push({
      path: concept_path,
      title: target,
      description: "External dependency of " + options.title + ".",
      concept_type: OKF_TYPE_EXTERNAL,
    })
  }
  // Per-directory index files (root included).
  for index_file in render_indexes(entries) {
    files.push(index_file)
  }
  // Generation log (needs a date, so only with a timestamp).
  match options.timestamp {
    Some(ts) => {
      let package_count = sorted.length()
      let external_count = external_targets.length()
      files.push(
        (
          OKF_LOG_FILE,
          render_log(ts, options.title, package_count, external_count),
        ),
      )
    }
    None => ()
  }
  files
}

///|
/// Reserve a concept file path under `dir` for `name`, escaping the final
/// segment with `_` while it would shadow a reserved OKF filename
/// (`index.md`, `log.md`) or an already-allocated path.
fn allocate_concept_path(
  taken : Map[String, Bool],
  dir : String,
  name : String,
) -> String {
  let mut base = name
  while true {
    let candidate = dir + "/" + base + ".md"
    let filename = base_of(candidate)
    if filename != OKF_INDEX_FILE &&
      filename != OKF_LOG_FILE &&
      !taken.contains(candidate) {
      taken.set(candidate, true)
      return candidate
    }
    base = base + "_"
  }
  // Unreachable: the loop always returns.
  dir + "/" + base + ".md"
}

///|
/// Markdown link to a concept, resolved through the allocated path map.
fn concept_link(
  concept_paths : Map[String, String],
  key : String,
  fallback_dir : String,
) -> String {
  let path = match concept_paths.get(key) {
    Some(path) => path
    None => fallback_dir + "/" + key + ".md"
  }
  "[" + key + "](/" + path + ")"
}

///|
/// Render one internal package concept document.
fn render_package_concept(
  pkg : OkfPackageConcept,
  dependents : Array[String],
  options : OkfBundleOptions,
  package_concept_paths : Map[String, String],
  external_concept_paths : Map[String, String],
) -> String {
  let norm = normalize_package_path(pkg.path)
  let frontmatter : Array[(String, OkfValue)] = [
    ("type", Str(OKF_TYPE_PACKAGE)),
    ("title", Str(norm)),
    ("description", Str(pkg.description)),
  ]
  if pkg.languages.length() > 0 {
    let tags = pkg.languages.copy()
    tags.sort()
    frontmatter.push(("tags", List(tags)))
  }
  frontmatter.push(("source", Str(norm)))
  match options.timestamp {
    Some(ts) => frontmatter.push(("timestamp", Str(ts)))
    None => ()
  }
  let buf = StringBuilder()
  buf.write_string(render_frontmatter(frontmatter))
  buf.write_string("\n")
  if pkg.overview.length() > 0 {
    buf.write_string(pkg.overview)
    buf.write_string("\n\n")
  }
  if pkg.declarations.length() > 0 {
    let decls = pkg.declarations.copy()
    decls.sort_by(fn(a, b) {
      let by_kind = a.kind.compare(b.kind)
      if by_kind != 0 {
        by_kind
      } else {
        a.name.compare(b.name)
      }
    })
    buf.write_string("# Schema\n\n")
    buf.write_string("| Name | Kind | Description |\n")
    buf.write_string("|------|------|-------------|\n")
    for decl in decls {
      buf.write_string("| `")
      buf.write_string(escape_table_cell(decl.name))
      buf.write_string("` | ")
      buf.write_string(escape_table_cell(decl.kind))
      buf.write_string(" | ")
      buf.write_string(escape_table_cell(decl.doc))
      buf.write_string(" |\n")
    }
    buf.write_string("\n")
  }
  // Every emitted link must resolve inside the bundle: drop internal
  // dependency lines whose target concept was not emitted (symmetric with
  // the known-package filter applied to backlinks).
  let deps : Array[OkfDepRef] = []
  for dep in pkg.depends_on {
    if dep.internal &&
      !package_concept_paths.contains(normalize_package_path(dep.target)) {
      continue
    }
    deps.push(dep)
  }
  if deps.length() > 0 {
    deps.sort_by(fn(a, b) {
      if a.internal != b.internal {
        if a.internal {
          -1
        } else {
          1
        }
      } else {
        a.target.compare(b.target)
      }
    })
    buf.write_string("# Dependencies\n\n")
    for dep in deps {
      let link = if dep.internal {
        concept_link(
          package_concept_paths,
          normalize_package_path(dep.target),
          OKF_PACKAGES_DIR,
        )
      } else {
        concept_link(
          external_concept_paths,
          sanitize_bundle_path(dep.target),
          OKF_DEPENDENCIES_DIR,
        )
      }
      buf.write_string("* Depends on ")
      buf.write_string(link)
      match dep.via {
        Some(via) => {
          buf.write_string(" (as `")
          buf.write_string(via)
          buf.write_string("`)")
        }
        None => ()
      }
      buf.write_string("\n")
    }
    buf.write_string("\n")
  }
  if dependents.length() > 0 {
    buf.write_string("# Dependents\n\n")
    for dependent in dependents {
      buf.write_string("* Used by ")
      buf.write_string(
        concept_link(package_concept_paths, dependent, OKF_PACKAGES_DIR),
      )
      buf.write_string("\n")
    }
    buf.write_string("\n")
  }
  if pkg.files.length() > 0 {
    let file_list = pkg.files.copy()
    file_list.sort()
    buf.write_string("# Files\n\n")
    for file in file_list {
      buf.write_string("* `")
      buf.write_string(file)
      buf.write_string("`\n")
    }
    buf.write_string("\n")
  }
  trim_trailing_newlines(buf.to_string()) + "\n"
}

///|
/// Render one external dependency concept document.
fn render_external_concept(
  target : String,
  dependents : Array[String],
  options : OkfBundleOptions,
  package_concept_paths : Map[String, String],
) -> String {
  let frontmatter : Array[(String, OkfValue)] = [
    ("type", Str(OKF_TYPE_EXTERNAL)),
    ("title", Str(target)),
    ("description", Str("External dependency of " + options.title + ".")),
  ]
  match options.timestamp {
    Some(ts) => frontmatter.push(("timestamp", Str(ts)))
    None => ()
  }
  let buf = StringBuilder()
  buf.write_string(render_frontmatter(frontmatter))
  buf.write_string("\n")
  if dependents.length() > 0 {
    buf.write_string("# Dependents\n\n")
    for dependent in dependents {
      buf.write_string("* Used by ")
      buf.write_string(
        concept_link(package_concept_paths, dependent, OKF_PACKAGES_DIR),
      )
      buf.write_string("\n")
    }
    buf.write_string("\n")
  }
  trim_trailing_newlines(buf.to_string()) + "\n"
}

///|
/// Render `index.md` for every directory that holds concepts (root included).
fn render_indexes(entries : Array[ConceptEntry]) -> Array[(String, String)] {
  // Collect every directory in the bundle ("" is the root).
  let dirs : Map[String, Bool] = Map([])
  dirs.set("", true)
  for entry in entries {
    let mut dir = parent_of(entry.path)
    while true {
      dirs.set(dir, true)
      if dir == "" {
        break
      }
      dir = parent_of(dir)
    }
  }
  // Count descendant concepts per directory for subdirectory descriptions.
  let descendant_counts : Map[String, Int] = Map([])
  for entry in entries {
    let mut dir = parent_of(entry.path)
    while true {
      descendant_counts.set(dir, descendant_counts.get(dir).unwrap_or(0) + 1)
      if dir == "" {
        break
      }
      dir = parent_of(dir)
    }
  }
  let dir_list : Array[String] = []
  for entry in dirs {
    dir_list.push(entry.0)
  }
  dir_list.sort()
  let result : Array[(String, String)] = []
  for dir in dir_list {
    let buf = StringBuilder()
    // Direct-child concepts grouped by type.
    let child_entries : Array[ConceptEntry] = []
    for entry in entries {
      if parent_of(entry.path) == dir {
        child_entries.push(entry)
      }
    }
    let type_names : Array[String] = []
    for entry in child_entries {
      if !type_names.contains(entry.concept_type) {
        type_names.push(entry.concept_type)
      }
    }
    type_names.sort()
    for type_name in type_names {
      buf.write_string("# ")
      buf.write_string(type_name)
      buf.write_string("\n\n")
      let group : Array[ConceptEntry] = []
      for entry in child_entries {
        if entry.concept_type == type_name {
          group.push(entry)
        }
      }
      group.sort_by(fn(a, b) { a.title.compare(b.title) })
      for entry in group {
        buf.write_string("* [")
        buf.write_string(entry.title)
        buf.write_string("](")
        buf.write_string(base_of(entry.path))
        buf.write_string(")")
        if entry.description.length() > 0 {
          buf.write_string(" - ")
          buf.write_string(entry.description)
        }
        buf.write_string("\n")
      }
      buf.write_string("\n")
    }
    // Direct subdirectories.
    let subdirs : Array[String] = []
    for candidate in dir_list {
      if candidate != "" && parent_of(candidate) == dir {
        subdirs.push(candidate)
      }
    }
    subdirs.sort()
    if subdirs.length() > 0 {
      buf.write_string("# Subdirectories\n\n")
      for subdir in subdirs {
        let count = descendant_counts.get(subdir).unwrap_or(0)
        buf.write_string("* [")
        buf.write_string(base_of(subdir))
        buf.write_string("](")
        buf.write_string(base_of(subdir))
        buf.write_string("/) - Contains ")
        buf.write_string(count.to_string())
        buf.write_string(" concept document(s).\n")
      }
      buf.write_string("\n")
    }
    let index_path = if dir == "" {
      OKF_INDEX_FILE
    } else {
      dir + "/" + OKF_INDEX_FILE
    }
    result.push((index_path, trim_trailing_newlines(buf.to_string()) + "\n"))
  }
  result
}

///|
/// Render the root `log.md` generation history.
fn render_log(
  timestamp : String,
  title : String,
  package_count : Int,
  external_count : Int,
) -> String {
  let buf = StringBuilder()
  buf.write_string("# Bundle Update Log\n\n## ")
  buf.write_string(date_of(timestamp))
  buf.write_string("\n\n* **Generation**: Generated ")
  buf.write_string(package_count.to_string())
  buf.write_string(" package concept(s) and ")
  buf.write_string(external_count.to_string())
  buf.write_string(" dependency concept(s) for ")
  buf.write_string(title)
  buf.write_string(".\n")
  buf.to_string()
}

///|
/// Normalize an analyzed package path into a bundle path segment:
/// strips leading `./` and `/`, unifies separators, and maps an empty
/// result (the analysis root itself) to `OKF_ROOT_CONCEPT`.
pub fn normalize_package_path(path : String) -> String {
  let sanitized = sanitize_bundle_path(path)
  if sanitized == "" {
    OKF_ROOT_CONCEPT
  } else {
    sanitized
  }
}

///|
/// Sanitize an arbitrary identifier into a safe bundle-relative path:
/// backslashes become slashes, drive/prefix colons become underscores,
/// leading `./` and `/` are dropped, `..` segments and empty segments are
/// removed.
pub fn sanitize_bundle_path(path : String) -> String {
  let chars = path.to_array()
  let unified : Array[Char] = []
  for ch in chars {
    if ch == '\\' {
      unified.push('/')
    } else if ch == ':' {
      unified.push('_')
    } else {
      unified.push(ch)
    }
  }
  let segments : Array[String] = []
  let current : Array[Char] = []
  for ch in unified {
    if ch == '/' {
      push_segment(segments, current)
    } else {
      current.push(ch)
    }
  }
  push_segment(segments, current)
  join_segments(segments)
}

///|
fn push_segment(segments : Array[String], current : Array[Char]) -> Unit {
  if current.length() == 0 {
    return
  }
  let segment = String::from_array(current)
  current.clear()
  if segment == "." || segment == ".." {
    return
  }
  segments.push(segment)
}

///|
fn join_segments(segments : Array[String]) -> String {
  let buf = StringBuilder()
  for i, segment in segments {
    if i > 0 {
      buf.write_string("/")
    }
    buf.write_string(segment)
  }
  buf.to_string()
}

///|
/// Parent directory of a bundle-relative path ("" at the top level).
/// Deliberately not @config.dirname: that helper follows OS-path semantics,
/// while bundle paths are a normalized `/`-only domain where the top level
/// is "" rather than ".".
fn parent_of(path : String) -> String {
  let last_slash = @config.find_last_char(path, '/')
  if last_slash <= 0 {
    ""
  } else {
    @config.substring(path, 0, last_slash)
  }
}

///|
/// Final path component of a bundle-relative path.
fn base_of(path : String) -> String {
  let last_slash = @config.find_last_char(path, '/')
  if last_slash < 0 {
    path
  } else {
    @config.substring_from(path, last_slash + 1)
  }
}

///|
/// Escape a value for use inside a markdown table cell.
fn escape_table_cell(s : String) -> String {
  let buf = StringBuilder()
  for ch in s.to_array() {
    match ch {
      '|' => buf.write_string("\\|")
      '\n' => buf.write_string(" ")
      '\r' => ()
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
/// The `YYYY-MM-DD` prefix of an ISO 8601 instant.
fn date_of(timestamp : String) -> String {
  let chars = timestamp.to_array()
  let result : Array[Char] = []
  for i = 0; i < chars.length() && i < 10; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
fn trim_trailing_newlines(s : String) -> String {
  let chars = s.to_array()
  let mut end = chars.length()
  while end > 0 && (chars[end - 1] == '\n' || chars[end - 1] == '\r') {
    end = end - 1
  }
  let result : Array[Char] = []
  for i = 0; i < end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
fn sorted_or_empty(values : Array[String]?) -> Array[String] {
  match values {
    Some(arr) => {
      let copy = arr.copy()
      copy.sort()
      copy
    }
    None => []
  }
}
