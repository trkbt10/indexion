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
/// Create a VFSEntry from a regular (non-archive) file.
pub fn entry_from_file(path : String) -> VFSEntry raise Error {
  let content = @fs.read_file_to_string(path)
  {
    virtual_path: path,
    content,
    archive_source: None,
    is_binary: false,
  }
}

///|
/// Resolve a list of file paths into VFSEntry items.
/// Archive files (detected via KGF registry) are expanded into their inner entries.
/// Regular files become single VFSEntry items.
pub fn resolve_paths(
  file_paths : Array[String],
  registry : @registry.KGFRegistry,
) -> Array[VFSEntry] {
  let entries : Array[VFSEntry] = []
  for path in file_paths {
    let language = match registry.detect_from_path(path) {
      Some(v) => v
      None => {
        // Unrecognized file — try to read as regular file anyway
        let entry = entry_from_file(path) catch { _ => continue }
        entries.push(entry)
        continue
      }
    }
    let spec = match registry.get_spec(language) {
      Some(v) => v
      None => {
        let entry = entry_from_file(path) catch { _ => continue }
        entries.push(entry)
        continue
      }
    }
    if is_archive_spec(spec) {
      let archive_spec = ArchiveSpec::from_spec(spec)
      let inner_entries = expand_archive(path, archive_spec) catch {
        _ => continue
      }
      for ie in inner_entries {
        entries.push(ie)
      }
    } else {
      let entry = entry_from_file(path) catch { _ => continue }
      entries.push(entry)
    }
  }
  entries
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
