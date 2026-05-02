/// Loader for the story folder convention.
///
/// Convention: under `<root>/`, two top-level directories carry meaning:
///   - `sources/`  → supply-side documents (n)
///   - `prose/`    → derived prose chapters (m)
///
/// Sub-folder names under `sources/` classify the source document:
///   - `sources/plot/...`        → SourceKind::Plot
///   - `sources/references/...`  → SourceKind::Reference
///   - `sources/scene-notes/...` → SourceKind::SceneNote
///   - anything else under sources/ → SourceKind::OtherSource
///
/// Files under `prose/` are loaded as ProseDoc in lexicographic order so that
/// numerical prefixes (01-, 02-, ...) drive natural ordering.

///|
/// Load a story dataset from disk by walking sources/ and prose/.
/// Returns None if the root has neither directory present.
pub fn load_story_dataset(root : String) -> StoryDataset? {
  let normalized_root = @config_paths.normalize_path(root)
  let sources_dir = @config_paths.join_path(normalized_root, "sources")
  let prose_dir = @config_paths.join_path(normalized_root, "prose")
  let sources = load_sources(sources_dir, normalized_root)
  let prose = load_prose(prose_dir, normalized_root)
  if sources.is_empty() && prose.is_empty() {
    return None
  }
  Some(StoryDataset::new(normalized_root, sources, prose))
}

///|
/// Walk sources/ and produce SourceDoc[] keyed by sub-folder kind.
fn load_sources(
  sources_dir : String,
  root : String,
) -> Array[SourceDoc] {
  let docs : Array[SourceDoc] = []
  if !directory_exists(sources_dir) {
    return docs
  }
  let opts = @pipeline.DiscoverOptions::new(
    root_dir=sources_dir,
    recursive=true,
  )
  let paths = @pipeline.discover_files([sources_dir], opts)
  let sorted = sort_paths(paths)
  for path in sorted {
    if !is_textual_path(path) {
      continue
    }
    let content = read_text_file(path)
    if content.length() == 0 {
      continue
    }
    let rel = @config_paths.relative_to(root, path)
    let kind = classify_source_kind(rel)
    let display_name = display_name_for_path(rel)
    docs.push(SourceDoc::new(rel, display_name, kind, content))
  }
  docs
}

///|
/// Walk prose/ and produce ProseDoc[].
fn load_prose(prose_dir : String, root : String) -> Array[ProseDoc] {
  let docs : Array[ProseDoc] = []
  if !directory_exists(prose_dir) {
    return docs
  }
  let opts = @pipeline.DiscoverOptions::new(
    root_dir=prose_dir,
    recursive=true,
  )
  let paths = @pipeline.discover_files([prose_dir], opts)
  let sorted = sort_paths(paths)
  for path in sorted {
    if !is_textual_path(path) {
      continue
    }
    let content = read_text_file(path)
    if content.length() == 0 {
      continue
    }
    let rel = @config_paths.relative_to(root, path)
    let display_name = display_name_for_path(rel)
    docs.push(ProseDoc::new(rel, display_name, content))
  }
  docs
}

///|
/// Classify a source document by its first sub-folder under sources/.
/// `rel_path` is e.g. "sources/plot/01-outline.md".
fn classify_source_kind(rel_path : String) -> SourceKind {
  let parts = split_path(rel_path)
  // expect parts[0] == "sources", parts[1] == sub-folder name (or filename if flat)
  if parts.length() < 3 {
    return OtherSource
  }
  match parts[1] {
    "plot" => Plot
    "plots" => Plot
    "references" => Reference
    "reference" => Reference
    "scene-notes" => SceneNote
    "scenenotes" => SceneNote
    "scenes" => SceneNote
    _ => OtherSource
  }
}

///|
/// Heuristic: only load files that look like text (markdown, txt, plain).
/// Story sources are author-authored documents; we deliberately exclude
/// images, archives, and binary blobs without inspecting their contents.
fn is_textual_path(path : String) -> Bool {
  let ext = @config_paths.extension(path)
  let lower = lowercase(ext)
  match lower {
    ".md" => true
    ".markdown" => true
    ".txt" => true
    ".text" => true
    ".rst" => true
    ".org" => true
    "" => true // extensionless prose chapters are allowed
    _ => false
  }
}

///|
/// Read a file's contents, returning empty string on failure.
fn read_text_file(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    @fs.IOError(_) => ""
  }
}

///|
/// Best-effort directory existence check.
fn directory_exists(path : String) -> Bool {
  @fs.path_exists(path)
}

///|
/// Split a path on '/' separators. Result has no empty segments at the start
/// for absolute paths.
fn split_path(path : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut has_chars = false
  for c in path {
    if c == '/' {
      if has_chars {
        parts.push(buf.to_string())
        buf.reset()
        has_chars = false
      }
    } else {
      buf.write_char(c)
      has_chars = true
    }
  }
  if has_chars {
    parts.push(buf.to_string())
  }
  parts
}

///|
/// Display name for a path: basename without the extension.
fn display_name_for_path(rel_path : String) -> String {
  let base = @config_paths.basename(rel_path)
  let ext = @config_paths.extension(base)
  if ext.length() == 0 || ext.length() >= base.length() {
    return base
  }
  let stem_len = base.length() - ext.length()
  @config_paths.substring(base, 0, stem_len)
}

///|
/// Stable lexicographic sort of file paths. Used to make NN- prefixes drive
/// natural ordering across runs.
fn sort_paths(paths : Array[String]) -> Array[String] {
  let copy : Array[String] = []
  for p in paths {
    copy.push(p)
  }
  copy.sort_by(fn(a, b) { a.compare(b) })
  copy
}

///|
/// Lowercase ASCII characters in a string.
fn lowercase(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    let code = c.to_int()
    if code >= 0x41 && code <= 0x5A {
      buf.write_char((code + 32).unsafe_to_char())
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}
