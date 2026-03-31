///|
/// # Wiki Reader
///
/// Reads wiki pages from .indexion/wiki/ directory.
/// wiki.json defines the page structure; .md files provide content.

///|
/// Load wiki data from a wiki directory.
/// Returns None if wiki.json doesn't exist or can't be parsed.
pub fn load_wiki(wiki_dir : String) -> WikiData? {
  let manifest_path = wiki_dir + "/wiki.json"
  let manifest_text = @fs.read_file_to_string(manifest_path) catch {
    _ => return None
  }
  let manifest : WikiManifest = @json.from_json(@json.parse(manifest_text)) catch {
    _ => return None
  }
  // Build page index from manifest
  let page_index : Map[String, ManifestPage] = {}
  for mp in manifest.pages {
    page_index[mp.id] = mp
  }
  // Read each page's .md file and build WikiPage
  let pages : Map[String, WikiPage] = {}
  for mp in manifest.pages {
    let md_path = wiki_dir + "/" + mp.file
    let content = @fs.read_file_to_string(md_path) catch { _ => "" }
    let sources = parse_source_refs(mp.sources)
    let headings = extract_headings(content)
    // Resolve children from manifest
    let children : Array[String] = []
    for child_id in mp.children {
      children.push(child_id)
    }
    // Resolve parent by scanning manifest for who claims this page as child
    let parent = find_parent(mp.id, manifest.pages)
    pages[mp.id] = WikiPage::new(
      id=mp.id,
      title=mp.title,
      content~,
      sources~,
      headings~,
      children~,
      parent~,
    )
  }
  // Build nav tree from manifest page hierarchy
  let nav = build_nav(manifest.pages)
  Some(WikiData::new(nav~, pages~))
}

///|
/// Parse source reference strings like "src/foo.mbt:45-120" into WikiSourceRef.
fn parse_source_refs(sources : Array[String]) -> Array[WikiSourceRef] {
  let result : Array[WikiSourceRef] = []
  for src in sources {
    let colon_idx = @config.find_last_char(src, ':')
    if colon_idx > 0 {
      let file = @common.substring(src, 0, colon_idx)
      let range_str = @common.substring(
        src,
        colon_idx + 1,
        src.to_array().length(),
      )
      let dash_parts = split_by_dash(range_str)
      if dash_parts.length() == 2 {
        let start = @common.parse_int(dash_parts[0])
        let end = @common.parse_int(dash_parts[1])
        result.push(WikiSourceRef::new(file~, start_line=start, end_line=end))
      } else {
        result.push(WikiSourceRef::new(file=src, start_line=0, end_line=0))
      }
    } else {
      result.push(WikiSourceRef::{ file: src, start_line: 0, end_line: 0 })
    }
  }
  result
}

///|
fn split_by_dash(s : String) -> Array[String] {
  let parts : Array[String] = []
  let buf : Array[Char] = []
  for c in s {
    if c == '-' {
      if buf.length() > 0 {
        parts.push(String::from_array(buf))
        buf.clear()
      }
    } else {
      buf.push(c)
    }
  }
  if buf.length() > 0 {
    parts.push(String::from_array(buf))
  }
  parts
}

///|
fn find_parent(page_id : String, pages : Array[ManifestPage]) -> String? {
  for mp in pages {
    for child_id in mp.children {
      if child_id == page_id {
        return Some(mp.id)
      }
    }
  }
  None
}

///|
fn build_nav(pages : Array[ManifestPage]) -> WikiNav {
  // Find root pages (those that are no one's child)
  let is_child : Map[String, Bool] = {}
  for mp in pages {
    for child_id in mp.children {
      is_child[child_id] = true
    }
  }
  let page_map : Map[String, ManifestPage] = {}
  for mp in pages {
    page_map[mp.id] = mp
  }
  let root_items : Array[WikiNavItem] = []
  for mp in pages {
    if not(is_child.contains(mp.id)) {
      root_items.push(build_nav_item(mp.id, page_map))
    }
  }
  WikiNav::new(pages=root_items)
}

///|
fn build_nav_item(
  page_id : String,
  page_map : Map[String, ManifestPage],
) -> WikiNavItem {
  match page_map.get(page_id) {
    Some(mp) => {
      let children : Array[WikiNavItem] = []
      for child_id in mp.children {
        children.push(build_nav_item(child_id, page_map))
      }
      WikiNavItem::new(id=mp.id, title=mp.title, children~)
    }
    None => WikiNavItem::new(id=page_id, title=page_id)
  }
}

///|
fn extract_headings(content : String) -> Array[WikiHeading] {
  let headings : Array[WikiHeading] = []
  let lines = @common.split_lines(content)
  for line in lines {
    if line.has_prefix("## ") {
      let text = @common.substring(line, 3, line.to_array().length())
      headings.push(
        WikiHeading::new(level=2, text~, anchor=@common.make_anchor(text)),
      )
    } else if line.has_prefix("### ") {
      let text = @common.substring(line, 4, line.to_array().length())
      headings.push(
        WikiHeading::new(level=3, text~, anchor=@common.make_anchor(text)),
      )
    } else if line.has_prefix("#### ") {
      let text = @common.substring(line, 5, line.to_array().length())
      headings.push(
        WikiHeading::new(level=4, text~, anchor=@common.make_anchor(text)),
      )
    }
  }
  headings
}
