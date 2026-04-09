///|
/// # Wiki pages manifest helpers
///
/// Shared utilities for loading and writing the wiki manifest and page files.
/// Used by `pages add` and `pages update` to eliminate duplicated I/O logic.

///|
/// Load the wiki manifest from wiki_dir.
/// Prints an error and returns None if loading or parsing fails.
pub fn load_manifest(
  wiki_dir : String,
) -> @wiki_types.WikiManifest? {
  let manifest_path = @wiki_types.wiki_manifest_path(wiki_dir)
  if !@fs.path_exists(manifest_path) {
    println("Error: No wiki manifest found at " + manifest_path)
    return None
  }
  let manifest_content = @fs.read_file_to_string(manifest_path) catch {
    e => {
      println("Error reading manifest: " + e.to_string())
      return None
    }
  }
  let manifest_json = @json.parse(manifest_content) catch {
    e => {
      println("Error parsing manifest: " + e.to_string())
      return None
    }
  }
  let manifest : @wiki_types.WikiManifest = @json.from_json(manifest_json) catch {
    e => {
      println("Error decoding manifest: " + e.to_string())
      return None
    }
  }
  Some(manifest)
}

///|
/// Write an updated manifest and page content file to wiki_dir.
/// Returns false if any write fails.
pub fn write_page(
  wiki_dir : String,
  manifest : @wiki_types.WikiManifest,
  page_id : String,
  content : String,
) -> Bool {
  let manifest_path = @wiki_types.wiki_manifest_path(wiki_dir)
  let manifest_json = manifest.to_json().stringify(indent=2)
  @fs.write_string_to_file(manifest_path, manifest_json) catch {
    e => {
      println("Error writing manifest: " + e.to_string())
      return false
    }
  }
  let page_path = wiki_dir + "/" + page_id + ".md"
  @fs.write_string_to_file(page_path, content) catch {
    e => {
      println("Error writing page file: " + e.to_string())
      return false
    }
  }
  true
}
