///|
/// # Wiki Interop — Shared Utilities
///
/// Backend-agnostic conversion helpers used by GitHub, GitLab, and future wiki backends.
/// Includes KGF spec loading, format detection, metadata handling, navigation,
/// and string processing.

///|
/// Wiki storage format.
pub enum WikiFormat {
  Indexion
  GitHub
  GitLab
  Unknown
}

///|
/// Loaded KGF spec context shared across wiki backends.
pub struct WikiBackendSpec {
  spec : @kgf_types.KGFSpec
  lexer : @kgf_lexer.Lexer
  peg : @kgf_peg.PEG
  nav_file : String
  home_file : String
  special_files : Array[String]
}

// --- KGF spec loading ---

///|
/// Load a named KGF wiki spec (e.g., "github-wiki", "gitlab-wiki").
pub fn load_wiki_spec(spec_name : String) -> WikiBackendSpec? {
  let reg = match @kgf_features.load_registry() {
    Some(r) => r
    None => return None
  }
  let spec = match reg.get_spec(spec_name) {
    Some(s) => s
    None => return None
  }
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let peg = @kgf_peg.build_peg(spec) catch { _ => return None }
  let nav_file = get_feature_string(spec, "nav_file", "")
  let home_file = get_feature_string(spec, "home_file", "")
  let special_files = match spec.get_feature("special_files") {
    Some(vals) => vals
    None => []
  }
  Some(WikiBackendSpec::{ spec, lexer, peg, nav_file, home_file, special_files })
}

///|
fn get_feature_string(
  spec : @kgf_types.KGFSpec,
  key : String,
  default : String,
) -> String {
  match spec.get_feature(key) {
    Some(vals) => if vals.length() > 0 { vals[0] } else { default }
    None => default
  }
}

// --- Format detection ---

///|
/// Registry of wiki backend configs, keyed by KGF spec language name.
/// Each wiki KGF spec (github-wiki, gitlab-wiki, etc.) maps to its config.
let wiki_backend_registry : Map[String, () -> WikiBackendConfig] = {
  let m : Map[String, () -> WikiBackendConfig] = {}
  m["github-wiki"] = github_config
  m["gitlab-wiki"] = gitlab_config
  m
}

///|
/// Detect which KGF wiki spec matches a directory.
/// Probes each registered wiki spec's home_file and nav_file markers.
/// Returns the spec language name, or None if no match.
pub fn detect_wiki_spec(dir : String) -> String? {
  let registry = @kgf_features.load_registry(specs_dir="kgfs", target_dir=".")
  let reg = match registry {
    Some(r) => r
    None => return None
  }
  for spec_entry in reg.specs {
    let lang = spec_entry.0
    let spec = spec_entry.1
    let home = get_feature_string(spec, "home_file", "")
    let nav = get_feature_string(spec, "nav_file", "")
    if home.length() == 0 && nav.length() == 0 {
      continue
    }
    let has_home = home.length() > 0 && @fs.path_exists(dir + "/" + home)
    let has_nav = nav.length() > 0 && @fs.path_exists(dir + "/" + nav)
    if has_home || has_nav {
      if wiki_backend_registry.contains(lang) {
        return Some(lang)
      }
    }
  }
  None
}

///|
/// Detect wiki format from directory contents.
pub fn detect_wiki_format(dir : String) -> WikiFormat {
  if @fs.path_exists(@types.wiki_manifest_path(dir)) {
    return WikiFormat::Indexion
  }
  match detect_wiki_spec(dir) {
    Some("github-wiki") => WikiFormat::GitHub
    Some("gitlab-wiki") => WikiFormat::GitLab
    Some(_) => WikiFormat::Unknown
    None => WikiFormat::Unknown
  }
}

///|
/// Load wiki from directory, auto-detecting format.
/// Uses KGF spec features to identify the wiki backend, then delegates
/// to the registered backend config.
pub fn load_wiki_auto(
  wiki_dir : String,
  registry? : @kgf_registry.KGFRegistry? = None,
) -> @types.WikiData? {
  if @fs.path_exists(@types.wiki_manifest_path(wiki_dir)) {
    return @reader.load_wiki(wiki_dir, registry~)
  }
  match detect_wiki_spec(wiki_dir) {
    Some(spec_name) =>
      match wiki_backend_registry.get(spec_name) {
        Some(config_fn) => load_external_wiki(wiki_dir, config_fn())
        None => None
      }
    None => None
  }
}

// --- Generic backend pipeline ---

///|
/// Shared invalid-in-filename characters (SoT for all backends).
let filename_invalid_chars : Array[Char] = [
  '(', ')', '&', ':', '*', '?', '"', '<', '>', '|', '\\',
]

///|
/// Generic slug: lowercase, spaces→hyphens, strip invalid chars.
/// Used as the default; backends can wrap this with additional transforms.
pub fn title_to_slug(title : String, lowercase? : Bool = true) -> String {
  let buf = StringBuilder::new()
  for c in title {
    if c == ' ' || c == '/' {
      buf.write_char('-')
    } else if filename_invalid_chars.contains(c) {
      continue
    } else if lowercase && c >= 'A' && c <= 'Z' {
      buf.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Convert slug to lowercase ID.
pub fn slug_to_id(slug : String) -> String {
  let buf = StringBuilder::new()
  for c in slug {
    if c >= 'A' && c <= 'Z' {
      buf.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Convert slug to display title (capitalize after hyphens).
pub fn slug_to_title(slug : String) -> String {
  let buf = StringBuilder::new()
  let mut capitalize_next = true
  for c in slug {
    if c == '-' {
      buf.write_char(' ')
      capitalize_next = true
    } else if c == '/' {
      buf.write_char('/')
      capitalize_next = true
    } else if capitalize_next && c >= 'a' && c <= 'z' {
      buf.write_char((c.to_int() - 32).unsafe_to_char())
      capitalize_next = false
    } else {
      buf.write_char(c)
      capitalize_next = false
    }
  }
  buf.to_string()
}

///|
/// Backend configuration for the generic load/export pipeline.
pub struct WikiBackendConfig {
  spec_name : String
  file_to_id : (String) -> String
  title_to_name : (String) -> String
  name_to_title : (String) -> String
  recursive : Bool
}

///|
/// Generic load for any external wiki backend.
pub fn load_external_wiki(
  wiki_dir : String,
  config : WikiBackendConfig,
) -> @types.WikiData? {
  let spec = match load_wiki_spec(config.spec_name) {
    Some(s) => s
    None => {
      println(
        "Warning: " +
        config.spec_name +
        " KGF spec not found. Ensure kgfs/ directory is accessible.",
      )
      return None
    }
  }
  let files = if config.recursive {
    list_md_files_recursive(wiki_dir, spec.special_files)
  } else {
    list_md_files(wiki_dir, spec.special_files)
  }
  if files.is_empty() {
    return None
  }
  let file_to_id = config.file_to_id
  let title_to_name = config.title_to_name
  let name_to_title = config.name_to_title
  let file_id_map : Map[String, String] = {}
  for f in files {
    file_id_map[f] = file_to_id(f)
  }
  let sidebar_path = wiki_dir + "/" + spec.nav_file
  let sidebar_content = @fs.read_file_to_string(sidebar_path) catch { _ => "" }
  let (nav_items, sidebar_titles) = if sidebar_content.length() > 0 {
    parse_sidebar_kgf(
      sidebar_content, file_id_map, file_to_id, title_to_name, spec,
    )
  } else {
    let items : Array[@types.WikiNavItem] = []
    let titles : Map[String, String] = {}
    for f in files {
      let id = file_id_map.get(f).unwrap_or(file_to_id(f))
      let title = name_to_title(f)
      items.push(@types.WikiNavItem::new(id~, title~))
      titles[id] = title
    }
    (items, titles)
  }
  let pages : Map[String, @types.WikiPage] = {}
  for f in files {
    let id = file_id_map.get(f).unwrap_or(file_to_id(f))
    let title = sidebar_titles.get(id).unwrap_or(name_to_title(f))
    let raw_content = @fs.read_file_to_string(wiki_dir + "/" + f + ".md") catch {
      _ => ""
    }
    let (content_without_meta, source_strings) = extract_sources_kgf(
      raw_content, spec,
    )
    let content = convert_wikilinks_to_internal(
      content_without_meta, file_id_map, file_to_id, title_to_name, spec,
    )
    let sources = parse_source_strings(source_strings)
    let headings = @reader.extract_headings(content)
    let children = find_children_for(id, nav_items)
    let parent = find_parent_in_nav(id, nav_items)
    pages[id] = @types.WikiPage::new(
      id~,
      title~,
      content~,
      file=f + ".md",
      sources~,
      headings~,
      children~,
      parent~,
    )
  }
  let nav = @types.WikiNav::new(pages=nav_items)
  Some(@types.WikiData::new(nav~, pages~))
}

///|
/// Generic export for any external wiki backend.
pub fn export_external_wiki(
  data : @types.WikiData,
  config : WikiBackendConfig,
) -> Array[(String, String)] {
  let spec = match load_wiki_spec(config.spec_name) {
    Some(s) => s
    None => {
      println("Warning: " + config.spec_name + " KGF spec not found.")
      return []
    }
  }
  let home_name = strip_md_ext(spec.home_file)
  let result : Array[(String, String)] = []
  let id_to_title : Map[String, String] = {}
  let id_to_name : Map[String, String] = {}
  let root_id = find_root_id(data.nav)
  let title_to_name = config.title_to_name
  for entry in data.pages {
    let id = entry.0
    let page = entry.1
    id_to_title[id] = page.title
    let name = if id == root_id { home_name } else { title_to_name(page.title) }
    id_to_name[id] = name
  }
  for entry in data.pages {
    let id = entry.0
    let page = entry.1
    let name = id_to_name.get(id).unwrap_or(title_to_name(page.title))
    let converted = convert_internal_to_wikilinks(
      page.content,
      id_to_name,
      id_to_title,
    )
    let sources_comment = embed_sources_comment(page.sources)
    let full_content = if sources_comment.length() > 0 {
      sources_comment + "\n" + converted
    } else {
      converted
    }
    result.push((name + ".md", full_content))
  }
  let sidebar = render_sidebar_wikilinks(
    data.nav,
    id_to_name,
    id_to_title,
    root_id,
    home_name,
  )
  result.push((spec.nav_file, sidebar))
  result
}

// --- Manifest generation ---

///|
/// Generate wiki.json manifest content from @types.WikiData.
pub fn generate_manifest_json(data : @types.WikiData, title : String) -> String {
  let page_entries : Array[(String, @types.WikiPage)] = []
  collect_pages_in_nav_order(data.nav.pages, data.pages, page_entries)
  let pages_json : Array[Json] = []
  for entry in page_entries {
    let (id, page) = entry
    let sources_json : Array[Json] = page.sources.map(fn(src) {
      src.file.to_json()
    })
    let children_json : Array[Json] = page.children.map(fn(c) { c.to_json() })
    let m : Map[String, Json] = {}
    m["id"] = id.to_json()
    m["title"] = page.title.to_json()
    m["file"] = (id + ".md").to_json()
    m["sources"] = Json::array(sources_json)
    m["children"] = Json::array(children_json)
    pages_json.push(Json::object(m))
  }
  let root : Map[String, Json] = {}
  root["title"] = title.to_json()
  root["pages"] = Json::array(pages_json)
  Json::object(root).stringify(indent=2) + "\n"
}

// --- Source metadata ---

///|
/// Embed sources as an HTML comment (shared across all backends).
pub fn embed_sources_comment(sources : Array[@types.WikiSourceRef]) -> String {
  if sources.is_empty() {
    return ""
  }
  let buf = StringBuilder::new()
  buf.write_string("<!-- indexion:sources ")
  for i, src in sources {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(src.file)
    if src.start_line > 0 || src.end_line > 0 {
      buf.write_string(":")
      buf.write_string(src.start_line.to_string())
      buf.write_string("-")
      buf.write_string(src.end_line.to_string())
    }
  }
  buf.write_string(" -->")
  buf.to_string()
}

///|
/// Extract META_COMMENT tokens containing indexion:sources metadata.
/// Returns (content_without_comments, source_strings).
pub fn extract_sources_kgf(
  content : String,
  spec : WikiBackendSpec,
) -> (String, Array[String]) {
  let tokens = spec.lexer.tokenize(content)
  let sources : Array[String] = []
  let removals : Array[(Int, Int)] = []
  for tok in tokens {
    if tok.kind == "META_COMMENT" {
      let text = tok.text
      match tok.value {
        Some(inner) => {
          let trimmed = @common.trim_ascii_spaces(inner)
          if trimmed.has_prefix("sources") {
            let after_key = @common.substring(
              trimmed,
              7,
              trimmed.to_array().length(),
            )
            for part in @common.split_by_char(after_key, ',') {
              let s = @common.trim_ascii_spaces(part)
              if s.length() > 0 {
                sources.push(s)
              }
            }
            removals.push((tok.pos, tok.pos + text.to_array().length()))
          }
        }
        None => ()
      }
    }
  }
  if removals.is_empty() {
    return (content, sources)
  }
  let chars = content.to_array()
  let buf = StringBuilder::new()
  let mut last = 0
  for removal in removals {
    let (start, end) = removal
    for i = last; i < start; i = i + 1 {
      buf.write_char(chars[i])
    }
    last = if end < chars.length() && chars[end] == '\n' {
      end + 1
    } else {
      end
    }
  }
  for i = last; i < chars.length(); i = i + 1 {
    buf.write_char(chars[i])
  }
  (buf.to_string(), sources)
}

///|
/// Parse source reference strings like "src/foo.mbt:45-120" into @types.WikiSourceRef.
pub fn parse_source_strings(
  sources : Array[String],
) -> Array[@types.WikiSourceRef] {
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
      let dash_pos = find_char_in_string(range_str, '-')
      if dash_pos > 0 {
        let start_str = @common.substring(range_str, 0, dash_pos)
        let end_str = @common.substring(
          range_str,
          dash_pos + 1,
          range_str.to_array().length(),
        )
        let start = @common.parse_int(start_str)
        let end_ = @common.parse_int(end_str)
        if start > 0 || end_ > 0 {
          result.push(
            @types.WikiSourceRef::new(file~, start_line=start, end_line=end_),
          )
        } else {
          result.push(@types.WikiSourceRef::new(file=src))
        }
      } else {
        result.push(@types.WikiSourceRef::new(file=src))
      }
    } else {
      result.push(@types.WikiSourceRef::new(file=src))
    }
  }
  result
}

// --- KGF-based link conversion ---

///|
/// Convert [[wiki links]] to wiki:// links using KGF parse events.
/// Works for any backend whose KGF grammar produces WikiLink events with wpath/alias labels.
pub fn convert_wikilinks_to_internal(
  content : String,
  filename_to_id : Map[String, String],
  filename_to_id_fn : (String) -> String,
  default_target_fn : (String) -> String,
  spec : WikiBackendSpec,
) -> String {
  let tokens = spec.lexer.tokenize(content)
  let events = match @kgf_peg.run_parse(spec.peg, spec.spec, "Doc", tokens) {
    Some(result) => result.get_events()
    None => return content
  }
  let replacements : Array[(Int, Int, String)] = []
  for event in events {
    let (rule_name, labels) = event
    if rule_name == "WikiLink" {
      let display = match labels.get("wpath") {
        Some(Json::String(s)) => s
        _ => continue
      }
      let start_pos = match labels.get("wpath_pos") {
        Some(Json::Number(n, ..)) => n.to_int() - 2
        _ => continue
      }
      let end_pos = match labels.get("_last_pos") {
        Some(Json::Number(n, ..)) =>
          match labels.get("_last_len") {
            Some(Json::Number(l, ..)) => n.to_int() + l.to_int()
            _ => continue
          }
        _ => continue
      }
      let target = match labels.get("alias") {
        Some(Json::String(s)) => s
        _ => default_target_fn(display)
      }
      let id = filename_to_id.get(target).unwrap_or(filename_to_id_fn(target))
      let replacement = "[" + display + "](wiki://" + id + ")"
      replacements.push((start_pos, end_pos, replacement))
    }
  }
  apply_replacements(content, replacements)
}

///|
/// Convert wiki:// links to [[wiki links]].
/// Used by backends that emit `[[Display|Target]]` format (GitHub, GitLab).
pub fn convert_internal_to_wikilinks(
  content : String,
  id_to_name : Map[String, String],
  id_to_title : Map[String, String],
) -> String {
  let chars = content.to_array()
  let len = chars.length()
  let buf = StringBuilder::new()
  let wiki_marker = "](wiki://"
  let marker_chars = wiki_marker.to_array()
  let marker_len = marker_chars.length()
  let mut i = 0
  while i < len {
    if chars[i] == '[' {
      let display_start = i + 1
      let mut j = display_start
      while j < len && chars[j] != ']' {
        j += 1
      }
      if j + marker_len - 1 < len {
        let mut is_wiki = true
        for k in 0..<(marker_len - 1) {
          if j + k >= len || chars[j + k] != marker_chars[k] {
            is_wiki = false
            break
          }
        }
        if is_wiki {
          let display = chars_to_string(chars, display_start, j)
          let id_start = j + marker_len - 1
          let mut id_end = id_start
          while id_end < len && chars[id_end] != ')' {
            id_end += 1
          }
          let page_id = chars_to_string(chars, id_start, id_end)
          let name = id_to_name.get(page_id).unwrap_or(display)
          let title = id_to_title.get(page_id).unwrap_or(display)
          if display == title {
            buf.write_string("[[")
            buf.write_string(title)
            buf.write_string("]]")
          } else {
            buf.write_string("[[")
            buf.write_string(display)
            buf.write_string("|")
            buf.write_string(name)
            buf.write_string("]]")
          }
          i = id_end + 1
          continue
        }
      }
    }
    buf.write_char(chars[i])
    i += 1
  }
  buf.to_string()
}

// --- Sidebar parsing (shared for [[]] link sidebars) ---

///|
/// Parse a sidebar file using KGF parse events.
/// Works for any backend whose sidebar uses `[[Display|Target]]` links in list items.
pub fn parse_sidebar_kgf(
  content : String,
  filename_to_id : Map[String, String],
  filename_to_id_fn : (String) -> String,
  default_target_fn : (String) -> String,
  spec : WikiBackendSpec,
) -> (Array[@types.WikiNavItem], Map[String, String]) {
  let lines = @common.split_lines(content)
  let titles : Map[String, String] = {}
  let entries : Array[(Int, String, String)] = []
  for line in lines {
    let indent = count_leading_spaces(line)
    let level = indent / 2
    let trimmed = @common.trim_ascii_spaces(line)
    if trimmed.has_prefix("* ") || trimmed.has_prefix("- ") {
      let tokens = spec.lexer.tokenize(line)
      match @kgf_peg.run_parse(spec.peg, spec.spec, "Doc", tokens) {
        Some(result) =>
          for event in result.get_events() {
            let (rule_name, labels) = event
            if rule_name == "WikiLink" {
              let display = match labels.get("wpath") {
                Some(Json::String(s)) => s
                _ => continue
              }
              let target = match labels.get("alias") {
                Some(Json::String(s)) => s
                _ => default_target_fn(display)
              }
              let id = filename_to_id
                .get(target)
                .unwrap_or(filename_to_id_fn(target))
              titles[id] = display
              entries.push((level, id, display))
              break
            }
          }
        None => ()
      }
    }
  }
  let nav_items = build_tree_from_entries(entries)
  (nav_items, titles)
}

// --- Navigation tree ---

///|
pub fn build_tree_from_entries(
  entries : Array[(Int, String, String)],
) -> Array[@types.WikiNavItem] {
  if entries.is_empty() {
    return []
  }
  let root_items : Array[@types.WikiNavItem] = []
  let stack : Array[(Int, String, String, Array[@types.WikiNavItem])] = []
  for entry in entries {
    let (level, id, title) = entry
    while stack.length() > 0 {
      let top = stack[stack.length() - 1]
      if top.0 >= level {
        let popped = stack.pop().unwrap()
        let item = @types.WikiNavItem::new(
          id=popped.1,
          title=popped.2,
          children=popped.3,
        )
        if stack.length() > 0 {
          stack[stack.length() - 1].3.push(item)
        } else {
          root_items.push(item)
        }
      } else {
        break
      }
    }
    stack.push((level, id, title, []))
  }
  while stack.length() > 0 {
    let popped = stack.pop().unwrap()
    let item = @types.WikiNavItem::new(
      id=popped.1,
      title=popped.2,
      children=popped.3,
    )
    if stack.length() > 0 {
      stack[stack.length() - 1].3.push(item)
    } else {
      root_items.push(item)
    }
  }
  root_items
}

///|
pub fn find_children_for(
  id : String,
  items : Array[@types.WikiNavItem],
) -> Array[String] {
  for item in items {
    if item.id == id {
      return item.children.map(fn(child) { child.id })
    }
    let found = find_children_for(id, item.children)
    if found.length() > 0 {
      return found
    }
  }
  []
}

///|
pub fn find_parent_in_nav(
  id : String,
  items : Array[@types.WikiNavItem],
) -> String? {
  for item in items {
    for child in item.children {
      if child.id == id {
        return Some(item.id)
      }
      match find_parent_in_nav(id, item.children) {
        Some(p) => return Some(p)
        None => ()
      }
    }
  }
  None
}

///|
pub fn find_root_id(nav : @types.WikiNav) -> String {
  if nav.pages.length() > 0 {
    nav.pages[0].id
  } else {
    "home"
  }
}

///|
pub fn collect_pages_in_nav_order(
  items : Array[@types.WikiNavItem],
  pages : Map[String, @types.WikiPage],
  result : Array[(String, @types.WikiPage)],
) -> Unit {
  for item in items {
    match pages.get(item.id) {
      Some(page) => result.push((item.id, page))
      None => ()
    }
    collect_pages_in_nav_order(item.children, pages, result)
  }
}

// --- File listing ---

///|
/// List .md files in a directory (flat, without extension), excluding special files.
pub fn list_md_files(
  dir : String,
  special_files : Array[String],
) -> Array[String] {
  let special_set : Map[String, Bool] = {}
  for f in special_files {
    special_set[strip_md_ext(f)] = true
  }
  let result : Array[String] = []
  let entries = @fs.read_dir(dir) catch { _ => return result }
  for entry in entries {
    if entry.has_suffix(".md") {
      let name = @common.substring(entry, 0, entry.to_array().length() - 3)
      if special_set.contains(name) {
        continue
      }
      result.push(name)
    }
  }
  result
}

///|
/// List .md files recursively (for nested directory wikis like GitLab).
/// Returns paths relative to dir, without .md extension.
pub fn list_md_files_recursive(
  dir : String,
  special_files : Array[String],
) -> Array[String] {
  let special_set : Map[String, Bool] = {}
  for f in special_files {
    special_set[strip_md_ext(f)] = true
  }
  let result : Array[String] = []
  list_md_files_recursive_inner(dir, "", special_set, result)
  result
}

///|
fn list_md_files_recursive_inner(
  base_dir : String,
  prefix : String,
  special_set : Map[String, Bool],
  result : Array[String],
) -> Unit {
  let entries = @fs.read_dir(base_dir) catch { _ => return }
  for entry in entries {
    let full_path = if base_dir.length() > 0 {
      base_dir + "/" + entry
    } else {
      entry
    }
    let relative = if prefix.length() > 0 {
      prefix + "/" + entry
    } else {
      entry
    }
    if entry.has_suffix(".md") {
      let name = @common.substring(
        relative,
        0,
        relative.to_array().length() - 3,
      )
      if special_set.contains(strip_md_ext(entry)) {
        continue
      }
      result.push(name)
    } else if @common.is_directory(full_path) && !entry.has_prefix(".") {
      list_md_files_recursive_inner(full_path, relative, special_set, result)
    }
  }
}

// --- Sidebar rendering (shared [[]] format) ---

///|
/// Render WikiNav as sidebar content with [[wiki links]].
pub fn render_sidebar_wikilinks(
  nav : @types.WikiNav,
  id_to_name : Map[String, String],
  id_to_title : Map[String, String],
  root_id : String,
  home_name : String,
) -> String {
  let buf = StringBuilder::new()
  for item in nav.pages {
    render_sidebar_item_wikilinks(
      buf, item, id_to_name, id_to_title, root_id, home_name, 0,
    )
  }
  buf.to_string()
}

///|
fn render_sidebar_item_wikilinks(
  buf : StringBuilder,
  item : @types.WikiNavItem,
  id_to_name : Map[String, String],
  id_to_title : Map[String, String],
  root_id : String,
  home_name : String,
  depth : Int,
) -> Unit {
  for _ in 0..<depth {
    buf.write_string("  ")
  }
  let name = id_to_name.get(item.id).unwrap_or(item.title)
  let title = id_to_title.get(item.id).unwrap_or(item.title)
  if item.id == root_id {
    buf.write_string("* [[")
    buf.write_string(title)
    buf.write_string("|")
    buf.write_string(home_name)
    buf.write_string("]]\n")
  } else {
    buf.write_string("* [[")
    buf.write_string(title)
    if title != name {
      buf.write_string("|")
      buf.write_string(name)
    }
    buf.write_string("]]\n")
  }
  for child in item.children {
    render_sidebar_item_wikilinks(
      buf,
      child,
      id_to_name,
      id_to_title,
      root_id,
      home_name,
      depth + 1,
    )
  }
}

// --- String helpers ---

///|
pub fn apply_replacements(
  content : String,
  replacements : Array[(Int, Int, String)],
) -> String {
  if replacements.is_empty() {
    return content
  }
  let chars = content.to_array()
  let buf = StringBuilder::new()
  let mut last = 0
  for rep in replacements {
    let (start, end, text) = rep
    for i = last; i < start; i = i + 1 {
      buf.write_char(chars[i])
    }
    buf.write_string(text)
    last = end
  }
  for i = last; i < chars.length(); i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
pub fn chars_to_string(chars : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
pub fn find_char_in_string(s : String, target : Char) -> Int {
  for i, c in s {
    if c == target {
      return i
    }
  }
  -1
}

///|
pub fn count_leading_spaces(s : String) -> Int {
  let mut count = 0
  for c in s {
    if c == ' ' {
      count += 1
    } else {
      break
    }
  }
  count
}

///|
pub fn strip_md_ext(filename : String) -> String {
  if filename.has_suffix(".md") {
    @common.substring(filename, 0, filename.to_array().length() - 3)
  } else {
    filename
  }
}
