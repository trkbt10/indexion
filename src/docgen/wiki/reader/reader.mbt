///|
/// # Wiki Reader
///
/// Reads wiki pages from .indexion/wiki/ directory (indexion native format).
/// wiki.json defines the page structure; .md files provide content.

///|
/// Load wiki data from a wiki directory (indexion format).
/// Returns None if wiki.json doesn't exist or can't be parsed.
pub fn load_wiki(wiki_dir : String) -> @types.WikiData? {
  let manifest_path = wiki_dir + "/wiki.json"
  let manifest_text = @fs.read_file_to_string(manifest_path) catch {
    _ => return None
  }
  let manifest : @types.WikiManifest = @json.from_json(
    @json.parse(manifest_text),
  ) catch {
    _ => return None
  }
  let page_index : Map[String, @types.ManifestPage] = {}
  for mp in manifest.pages {
    page_index[mp.id] = mp
  }
  let pages : Map[String, @types.WikiPage] = {}
  for mp in manifest.pages {
    let md_path = wiki_dir + "/" + mp.file
    let content = @fs.read_file_to_string(md_path) catch { _ => "" }
    let sources = parse_source_refs(mp.sources)
    let headings = extract_headings(content)
    let children : Array[String] = []
    for child_id in mp.children {
      children.push(child_id)
    }
    let parent = find_parent(mp.id, manifest.pages)
    pages[mp.id] = @types.WikiPage::new(
      id=mp.id,
      title=mp.title,
      content~,
      sources~,
      headings~,
      children~,
      parent~,
    )
  }
  let nav = build_nav(manifest.pages)
  Some(@types.WikiData::new(nav~, pages~))
}

///|
/// Extract headings from markdown content for ToC.
pub fn extract_headings(content : String) -> Array[@types.WikiHeading] {
  let headings : Array[@types.WikiHeading] = []
  let lines = @common.split_lines(content)
  for line in lines {
    if line.has_prefix("## ") {
      let text = @common.substring(line, 3, line.to_array().length())
      headings.push(
        @types.WikiHeading::new(
          level=2,
          text~,
          anchor=@common.make_anchor(text),
        ),
      )
    } else if line.has_prefix("### ") {
      let text = @common.substring(line, 4, line.to_array().length())
      headings.push(
        @types.WikiHeading::new(
          level=3,
          text~,
          anchor=@common.make_anchor(text),
        ),
      )
    } else if line.has_prefix("#### ") {
      let text = @common.substring(line, 5, line.to_array().length())
      headings.push(
        @types.WikiHeading::new(
          level=4,
          text~,
          anchor=@common.make_anchor(text),
        ),
      )
    }
  }
  headings
}

// --- Internal helpers ---

///|
fn parse_source_refs(sources : Array[String]) -> Array[@types.WikiSourceRef] {
  let result : Array[@types.WikiSourceRef] = []
  for src in sources {
    let colon_idx = @config.find_last_char(src, ':')
    if colon_idx > 0 {
      let file = @common.substring(src, 0, colon_idx)
      let range_str = @common.substring(
        src,
        colon_idx + 1,
        src.to_array().length(),
      )
      let dash_parts = @common.split_by_char(range_str, '-')
      if dash_parts.length() == 2 {
        let start = @common.parse_int(dash_parts[0])
        let end = @common.parse_int(dash_parts[1])
        result.push(
          @types.WikiSourceRef::new(file~, start_line=start, end_line=end),
        )
      } else {
        result.push(@types.WikiSourceRef::new(file=src))
      }
    } else {
      result.push(@types.WikiSourceRef::new(file=src))
    }
  }
  result
}

///|
fn find_parent(page_id : String, pages : Array[@types.ManifestPage]) -> String? {
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
fn build_nav(pages : Array[@types.ManifestPage]) -> @types.WikiNav {
  let is_child : Map[String, Bool] = {}
  for mp in pages {
    for child_id in mp.children {
      is_child[child_id] = true
    }
  }
  let page_map : Map[String, @types.ManifestPage] = {}
  for mp in pages {
    page_map[mp.id] = mp
  }
  let root_items : Array[@types.WikiNavItem] = []
  for mp in pages {
    if !is_child.contains(mp.id) {
      root_items.push(build_nav_item(mp.id, page_map))
    }
  }
  @types.WikiNav::new(pages=root_items)
}

///|
fn build_nav_item(
  page_id : String,
  page_map : Map[String, @types.ManifestPage],
) -> @types.WikiNavItem {
  match page_map.get(page_id) {
    Some(mp) => {
      let children : Array[@types.WikiNavItem] = []
      for child_id in mp.children {
        children.push(build_nav_item(child_id, page_map))
      }
      @types.WikiNavItem::new(id=mp.id, title=mp.title, children~)
    }
    None => @types.WikiNavItem::new(id=page_id, title=page_id)
  }
}
