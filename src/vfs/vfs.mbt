///|
/// Virtual filesystem layer for transparent archive traversal.
/// Maps real files and archive entries into a unified VFSEntry abstraction.
///
/// Path convention: archive entries use "archive.pptx!/inner/path" notation.
/// The "!" separator is chosen because it cannot appear in filesystem paths.

///|
/// Separator between archive path and inner entry path.
let archive_separator : String = "!/"

///|
/// A virtual file entry — either a real file or an entry inside an archive.
pub struct VFSEntry {
  /// Display/identification path.
  /// Real files: "src/main.mbt"
  /// Archive entries: "docs/report.pptx!/ppt/slides/slide1.xml"
  virtual_path : String
  /// The content as a string (UTF-8 decoded for text, base64 encoded for binary).
  content : String
  /// If this entry came from an archive, the archive's real path.
  archive_source : String?
  /// Whether the content is base64-encoded binary data.
  is_binary : Bool
}

///|
/// Configuration for archive expansion.
/// Derived from KGF spec features (content_type: archive).
pub struct ArchiveSpec {
  /// Glob patterns for entries to include from the archive.
  inner_includes : Array[String]
  /// Glob patterns for entries to exclude from the archive.
  inner_excludes : Array[String]
}

///|
/// Build an ArchiveSpec from KGF spec features.
/// Reads "inner_includes" and "inner_excludes" feature arrays.
pub fn ArchiveSpec::from_spec(spec : @kgf_types.KGFSpec) -> ArchiveSpec {
  let inner_includes = match spec.get_feature("inner_includes") {
    Some(vals) => vals
    None => []
  }
  let inner_excludes = match spec.get_feature("inner_excludes") {
    Some(vals) => vals
    None => []
  }
  { inner_includes, inner_excludes }
}

///|
/// Check if a KGF spec declares content_type: archive.
pub fn is_archive_spec(spec : @kgf_types.KGFSpec) -> Bool {
  match spec.get_feature("content_type") {
    Some(values) =>
      for v in values {
        if v == "archive" {
          return true
        }
      } nobreak {
        false
      }
    None => false
  }
}

///|
/// Expand a single archive file into VFSEntry items.
/// Text entries (UTF-8 decodable) get their content as-is.
/// Binary entries get base64-encoded content.
pub fn expand_archive(
  archive_path : String,
  archive_spec : ArchiveSpec,
) -> Array[VFSEntry] raise Error {
  let zip_files = @zip.extract_filtered(
    archive_path,
    includes=archive_spec.inner_includes,
    excludes=archive_spec.inner_excludes,
  )
  let entries : Array[VFSEntry] = []
  for zf in zip_files {
    let virtual_path = archive_path + archive_separator + zf.name
    match @zip.decode_utf8(zf.data) {
      Some(text) =>
        entries.push(
          {
            virtual_path,
            content: text,
            archive_source: Some(archive_path),
            is_binary: false,
          },
        )
      None =>
        entries.push(
          {
            virtual_path,
            content: @zip.encode_base64(zf.data),
            archive_source: Some(archive_path),
            is_binary: true,
          },
        )
    }
  }
  entries
}

///|
/// Extract concatenated text content from an archive file.
/// Returns all non-binary inner entries joined by newlines.
/// This is the SoT for "read an archive as a single document".
pub fn extract_text_content(
  archive_path : String,
  archive_spec : ArchiveSpec,
) -> String raise Error {
  let entries = expand_archive(archive_path, archive_spec)
  let buf = StringBuilder::new()
  let mut has_content = false
  for entry in entries {
    if entry.is_binary {
      continue
    }
    if has_content {
      buf.write_string("\n")
    }
    buf.write_string(entry.content)
    has_content = true
  }
  buf.to_string()
}

///|
/// Extract individual text entries from an archive as (virtual_path, content) pairs.
/// This is the SoT for "enumerate an archive's text files for per-file comparison".
pub fn extract_text_entries(
  archive_path : String,
  archive_spec : ArchiveSpec,
) -> Array[(String, String)] raise Error {
  let entries = expand_archive(archive_path, archive_spec)
  let result : Array[(String, String)] = []
  for entry in entries {
    if entry.is_binary {
      continue
    }
    result.push((entry.virtual_path, entry.content))
  }
  result
}

///|
/// Try to extract concatenated text from an archive, given a KGF spec.
/// Returns None if the spec is not an archive type.
/// This is the single entry point for "does this spec represent an archive,
/// and if so, give me its text content".
pub fn try_extract_archive_text(
  path : String,
  spec : @kgf_types.KGFSpec,
) -> String?? raise Error {
  if !is_archive_spec(spec) {
    return None
  }
  let archive_spec = ArchiveSpec::from_spec(spec)
  let content = extract_text_content(path, archive_spec)
  if content.length() > 0 {
    Some(Some(content))
  } else {
    Some(None)
  }
}

///|
/// Try to extract individual text entries from an archive, given a KGF spec.
/// Returns None if the spec is not an archive type.
pub fn try_extract_archive_entries(
  path : String,
  spec : @kgf_types.KGFSpec,
) -> Array[(String, String)]? raise Error {
  if !is_archive_spec(spec) {
    return None
  }
  let archive_spec = ArchiveSpec::from_spec(spec)
  Some(extract_text_entries(path, archive_spec))
}

///|
/// Check if a path is a virtual (archive-internal) path.
/// Virtual paths contain the "!/" separator (e.g. "report.pptx!/ppt/slides/slide1.xml").
pub fn is_virtual_path(path : String) -> Bool {
  let len = path.length()
  let mut i = 0
  while i + 1 < len {
    if path[i] == '!' && path[i + 1] == '/' {
      return true
    }
    i += 1
  }
  false
}

///|
/// Parse a virtual path into (archive_path, inner_path) if it contains the archive separator.
/// Returns None for regular file paths.
pub fn parse_virtual_path(virtual_path : String) -> (String, String?)  {
  // Search for "!/" in the path
  let len = virtual_path.length()
  let sep_len = archive_separator.length()
  let mut i = 0
  while i + sep_len <= len {
    if virtual_path[i] == '!' && i + 1 < len && virtual_path[i + 1] == '/' {
      // Found separator at position i
      let archive_part = virtual_path[:i].to_string()
      let inner_part = virtual_path[i + sep_len:].to_string()
      return (archive_part, Some(inner_part))
    }
    i += 1
  }
  (virtual_path, None)
}

///|
/// Extract just the inner path portion from a virtual path.
/// For regular paths, returns the path itself.
pub fn inner_path(virtual_path : String) -> String {
  match parse_virtual_path(virtual_path) {
    (_, Some(inner)) => inner
    (path, None) => path
  }
}
