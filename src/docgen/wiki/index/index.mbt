///|
/// # Wiki Index
///
/// Auto-generated category catalog and LLM navigation entry point.
/// Inspired by Karpathy's index.md and Graphify's index.md.

///|
/// A category grouping pages by their source directory.
pub struct IndexCategory {
  name : String
  pages : Array[(String, String)] // (page_id, page_title)
}

///|
/// A hub page — most-linked page in the wiki (Graphify's "God Nodes").
pub struct HubPage {
  page_id : String
  title : String
  incoming_link_count : Int
}

///|
/// The complete index content ready for rendering.
pub struct WikiIndex {
  categories : Array[IndexCategory]
  hub_pages : Array[HubPage]
  recent_changes : Array[(String, String)] // (page_id, operation)
  total_pages : Int
}

///|
/// Build the wiki index from wiki data and optional log.
pub fn build_index(
  wiki : @wiki_types.WikiData,
  log : @wiki_log.WikiLog?,
) -> WikiIndex {
  let categories = build_categories(wiki)
  let hub_pages = find_hub_pages(wiki)
  let recent_changes = match log {
    Some(l) => extract_recent_changes(l)
    None => []
  }
  {
    categories,
    hub_pages,
    recent_changes,
    total_pages: wiki.pages.length(),
  }
}

///|
/// Render the index as markdown content suitable for a wiki page.
pub fn WikiIndex::to_markdown(self : WikiIndex) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Wiki Index\n\n")
  buf.write_string(
    "This index catalogs all " +
    self.total_pages.to_string() +
    " pages in this wiki.\n\n",
  )
  // Navigation hint for LLMs
  buf.write_string("## How to Navigate This Wiki\n\n")
  buf.write_string(
    "Start with the **Hub Pages** below — these are the most interconnected pages.\n",
  )
  buf.write_string(
    "Each links to related pages, forming a navigable knowledge graph.\n",
  )
  buf.write_string(
    "For specific topics, browse the **Categories** section.\n\n",
  )
  // Hub pages
  if self.hub_pages.length() > 0 {
    buf.write_string("## Hub Pages\n\n")
    buf.write_string(
      "Most-linked pages that serve as knowledge hubs:\n\n",
    )
    for hub in self.hub_pages {
      buf.write_string(
        "- [" +
        hub.title +
        "](wiki://" +
        hub.page_id +
        ") — " +
        hub.incoming_link_count.to_string() +
        " incoming links\n",
      )
    }
    buf.write_string("\n")
  }
  // Categories
  if self.categories.length() > 0 {
    buf.write_string("## Categories\n\n")
    for category in self.categories {
      buf.write_string("### " + category.name + "\n\n")
      for pair in category.pages {
        let (page_id, title) = pair
        buf.write_string(
          "- [" + title + "](wiki://" + page_id + ")\n",
        )
      }
      buf.write_string("\n")
    }
  }
  // Recent changes
  if self.recent_changes.length() > 0 {
    buf.write_string("## Recent Changes\n\n")
    for pair in self.recent_changes {
      let (page_id, operation) = pair
      buf.write_string("- " + operation + ": " + page_id + "\n")
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

// --- Internal helpers ---

///|
/// Categorize pages by the top-level directory of their source references.
fn build_categories(wiki : @wiki_types.WikiData) -> Array[IndexCategory] {
  let dir_pages : Map[String, Array[(String, String)]] = {}
  let uncategorized : Array[(String, String)] = []
  for entry in wiki.pages {
    let (page_id, page) = (entry.0, entry.1)
    if page.sources.length() == 0 {
      uncategorized.push((page_id, page.title))
      continue
    }
    // Use the first source's top-level directory as category
    let top_dir = extract_top_directory(page.sources[0].file)
    if top_dir.length() == 0 {
      uncategorized.push((page_id, page.title))
      continue
    }
    match dir_pages.get(top_dir) {
      Some(arr) => arr.push((page_id, page.title))
      None => dir_pages[top_dir] = [(page_id, page.title)]
    }
  }
  let categories : Array[IndexCategory] = []
  // Sort categories by name
  let names : Array[String] = []
  for entry in dir_pages {
    names.push(entry.0)
  }
  names.sort()
  for name in names {
    match dir_pages.get(name) {
      Some(pages) => categories.push({ name, pages })
      None => ()
    }
  }
  if uncategorized.length() > 0 {
    categories.push({ name: "Uncategorized", pages: uncategorized })
  }
  categories
}

///|
/// Extract the top-level directory from a file path.
fn extract_top_directory(path : String) -> String {
  let chars = path.to_array()
  let buf = StringBuilder::new()
  for c in chars {
    if c == '/' {
      break
    }
    buf.write_char(c)
  }
  let result = buf.to_string()
  // If result equals the full path (no slash found), it's a root file
  if result == path {
    return ""
  }
  result
}

///|
/// Find hub pages — pages with the most incoming links from other pages.
fn find_hub_pages(wiki : @wiki_types.WikiData) -> Array[HubPage] {
  let link_counts : Map[String, Int] = {}
  let wiki_prefix = "wiki://"
  let prefix_chars = wiki_prefix.to_array()
  let prefix_len = prefix_chars.length()
  for entry in wiki.pages {
    let page = entry.1
    let content_chars = page.content.to_array()
    let content_len = content_chars.length()
    let mut pos = 0
    while pos <= content_len - prefix_len {
      // Check if wiki:// prefix matches at this position
      let mut matched = true
      for j in 0..<prefix_len {
        if content_chars[pos + j] != prefix_chars[j] {
          matched = false
          break
        }
      }
      if !matched {
        pos += 1
        continue
      }
      // Extract target page ID
      let start = pos + prefix_len
      let mut end = start
      while end < content_len {
        let c = content_chars[end]
        if c == ')' || c == ']' || c == ' ' || c == '\n' || c == '#' ||
          c == '"' || c == '\'' {
          break
        }
        end += 1
      }
      if end > start {
        let buf = StringBuilder::new()
        for i in start..<end {
          buf.write_char(content_chars[i])
        }
        let target_id = buf.to_string()
        if wiki.pages.contains(target_id) {
          let count = match link_counts.get(target_id) {
            Some(c) => c
            None => 0
          }
          link_counts[target_id] = count + 1
        }
      }
      pos = end
    }
  }
  // Sort by link count descending, take top 10
  let hub_entries : Array[(String, Int)] = []
  for entry in link_counts {
    hub_entries.push((entry.0, entry.1))
  }
  hub_entries.sort_by(fn(a, b) { b.1.compare(a.1) })
  let max_hubs = 10
  let result : Array[HubPage] = []
  for i in 0..<hub_entries.length() {
    if i >= max_hubs {
      break
    }
    let (page_id, count) = hub_entries[i]
    if count < 2 {
      break
    }
    let title = match wiki.pages.get(page_id) {
      Some(page) => page.title
      None => page_id
    }
    result.push({ page_id, title, incoming_link_count: count })
  }
  result
}

///|
/// Extract recent changes from the log (last 20 entries that affected pages).
fn extract_recent_changes(
  log : @wiki_log.WikiLog,
) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  let seen : Map[String, Bool] = {}
  let entries = log.tail(50)
  // Walk backwards to get most recent first
  let len = entries.length()
  for idx in 0..<len {
    let entry = entries[len - 1 - idx]
    for page_id in entry.affected_pages {
      if !seen.contains(page_id) {
        seen[page_id] = true
        result.push((page_id, entry.operation))
        if result.length() >= 20 {
          return result
        }
      }
    }
  }
  result
}
