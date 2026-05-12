///|
/// Load owner-specific wiki pages, match wiki sources to owner directories, and
/// hash documentation knowledge for the agent orient cache.
pub fn collect_wiki_docs(
  wiki_dir : String,
  owner_dirs : Array[String],
) -> Array[LocalDocSource] {
  let result : Array[LocalDocSource] = []
  let manifest = load_wiki_manifest(wiki_dir)
  match manifest {
    None => result
    Some(m) => {
      for page in m.pages {
        if !wiki_page_is_owner_specific(page) {
          continue
        }
        let content_path = wiki_dir + "/" + page.file
        let content = @fs.read_file_to_string(content_path) catch {
          _ => continue
        }
        for owner in owner_dirs {
          if !wiki_page_covers_owner(page, owner) {
            continue
          }
          let doc_path = content_path + "#" + page.id
          if doc_source_exists(result, doc_path, owner) {
            continue
          }
          result.push({
            path: doc_path,
            owner,
            source_hash: @cas_hash.compute_hash(content).to_string(),
            content: "Wiki page " + page.id + " " + page.title + "\n" + content,
          })
        }
      }
      result
    }
  }
}

///|
pub fn load_wiki_manifest(wiki_dir : String) -> LocalWikiManifest? {
  let content = @fs.read_file_to_string(wiki_dir + "/wiki.json") catch {
    _ => return None
  }
  let json = @json.parse(content) catch { _ => return None }
  let manifest : LocalWikiManifest = @json.from_json(json) catch {
    _ => return None
  }
  Some(manifest)
}

///|
pub fn wiki_page_is_owner_specific(page : LocalWikiPage) -> Bool {
  page.sources.length() == 1
}

///|
pub fn wiki_page_covers_owner(page : LocalWikiPage, owner : String) -> Bool {
  for source in page.sources {
    if source_matches_owner(source, owner) {
      return true
    }
  }
  false
}

///|
pub fn source_matches_owner(source : String, owner : String) -> Bool {
  let source_path = trim_trailing_slash(source)
  let owner_path = trim_trailing_slash(owner)
  source_path == owner_path || source_path.has_prefix(owner_path + "/")
}

///|
pub fn trim_trailing_slash(path : String) -> String {
  let mut end = path.length()
  while end > 0 && path[end - 1] == '/' {
    end -= 1
  }
  @config_paths.substring(path, 0, end)
}

///|
pub fn doc_source_exists(
  docs : Array[LocalDocSource],
  path : String,
  owner : String,
) -> Bool {
  for doc in docs {
    if doc.path == path && doc.owner == owner {
      return true
    }
  }
  false
}

///|
pub fn knowledge_hash(wiki_docs : Array[LocalDocSource]) -> String {
  let parts : Array[String] = []
  for doc in wiki_docs {
    parts.push(doc.owner + "\t" + doc.path + "\t" + doc.source_hash)
  }
  parts.sort()
  @cas_hash.compute_hash(parts.join("\n")).to_string()
}

///|
pub fn is_documentation_path(path : String) -> Bool {
  path.has_suffix(".md") || path.has_suffix(".mbt.md")
}
