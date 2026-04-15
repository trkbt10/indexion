///|
/// # Wiki Lint
///
/// Structural integrity checks for wiki content.
/// All checks are deterministic — no LLM required.

///|
/// Severity level for lint issues.
pub(all) enum LintSeverity {
  Error
  Warning
  Info
}

///|
pub fn LintSeverity::to_string(self : LintSeverity) -> String {
  match self {
    Error => "error"
    Warning => "warning"
    Info => "info"
  }
}

///|
pub fn LintSeverity::priority(self : LintSeverity) -> Int {
  match self {
    Error => 1
    Warning => 2
    Info => 3
  }
}

///|
/// A single lint issue found during wiki inspection.
pub struct LintIssue {
  severity : LintSeverity
  /// Check category: "broken-link", "orphan", "missing-xref",
  /// "stale-source", "empty", "manifest-mismatch"
  check : String
  page_id : String
  message : String
  suggestion : String
}

///|
/// Full lint report.
pub struct LintReport {
  total_pages : Int
  issues : Array[LintIssue]
}

///|
pub fn LintReport::new(total_pages~ : Int) -> LintReport {
  { total_pages, issues: [] }
}

///|
pub fn LintReport::add(self : LintReport, issue : LintIssue) -> Unit {
  self.issues.push(issue)
}

///|
pub fn LintReport::error_count(self : LintReport) -> Int {
  let mut count = 0
  for issue in self.issues {
    match issue.severity {
      Error => count += 1
      _ => ()
    }
  }
  count
}

///|
pub fn LintReport::warning_count(self : LintReport) -> Int {
  let mut count = 0
  for issue in self.issues {
    match issue.severity {
      Warning => count += 1
      _ => ()
    }
  }
  count
}

///|
/// Run all lint checks on the given wiki data.
/// `wiki_dir` is the directory containing the wiki files (for file-system checks).
pub fn lint(wiki : @wiki_types.WikiData, wiki_dir~ : String) -> LintReport {
  let report = LintReport::new(total_pages=wiki.pages.length())
  check_broken_links(wiki, report)
  check_orphan_pages(wiki, report)
  check_missing_cross_references(wiki, report)
  check_stale_sources(wiki, wiki_dir, report)
  check_empty_pages(wiki, report)
  check_manifest_file_mismatch(wiki, wiki_dir, report)
  report
}

///|
/// Check 1: Broken internal links.
/// Scan page content for wiki:// links where the target page ID does not exist.
/// Links inside backtick code spans (e.g. `wiki://page-id`) are skipped.
fn check_broken_links(wiki : @wiki_types.WikiData, report : LintReport) -> Unit {
  let wiki_link_prefix = "wiki://"
  for entry in wiki.pages {
    let (page_id, page) = (entry.0, entry.1)
    let content = page.content
    let mut pos = 0
    while pos < content.length() {
      let idx = find_substring(content, wiki_link_prefix, from=pos)
      if idx < 0 {
        break
      }
      let start = idx + wiki_link_prefix.length()
      let end = find_link_end(content, start)
      // Skip links inside backtick code spans
      if is_in_code_span(content, idx) {
        pos = end
        continue
      }
      let target_id = substring(content, start, end)
      // Strip anchor fragment if present (wiki://page-id#heading)
      let target_base = match find_char(target_id, '#') {
        Some(hash_pos) => substring(target_id, 0, hash_pos)
        None => target_id
      }
      if target_base.length() > 0 && !wiki.pages.contains(target_base) {
        report.add({
          severity: Error,
          check: "broken-link",
          page_id,
          message: "Link to non-existent page: " + target_base,
          suggestion: "Remove the link or create the target page",
        })
      }
      pos = end
    }
  }
}

///|
/// Check 2: Orphan pages.
/// Pages not reachable from the navigation tree and not linked by any other page.
fn check_orphan_pages(wiki : @wiki_types.WikiData, report : LintReport) -> Unit {
  // Collect all page IDs reachable from nav tree
  let nav_reachable : Map[String, Bool] = {}
  for item in wiki.nav.pages {
    collect_nav_ids(item, nav_reachable)
  }
  // Collect all page IDs linked from other pages via wiki:// or children
  let linked : Map[String, Bool] = {}
  let wiki_link_prefix = "wiki://"
  for entry in wiki.pages {
    let page = entry.1
    // Children are linked
    for child_id in page.children {
      linked[child_id] = true
    }
    // Scan content for wiki:// links (skip code spans)
    let content = page.content
    let mut pos = 0
    while pos < content.length() {
      let idx = find_substring(content, wiki_link_prefix, from=pos)
      if idx < 0 {
        break
      }
      let start = idx + wiki_link_prefix.length()
      let end = find_link_end(content, start)
      if is_in_code_span(content, idx) {
        pos = end
        continue
      }
      let target_id = substring(content, start, end)
      let target_base = match find_char(target_id, '#') {
        Some(hash_pos) => substring(target_id, 0, hash_pos)
        None => target_id
      }
      if target_base.length() > 0 {
        linked[target_base] = true
      }
      pos = end
    }
  }
  // Report pages not in nav and not linked
  for entry in wiki.pages {
    let page_id = entry.0
    if !nav_reachable.contains(page_id) && !linked.contains(page_id) {
      report.add({
        severity: Warning,
        check: "orphan",
        page_id,
        message: "Page is not reachable from navigation or any link",
        suggestion: "Add to navigation tree or link from a related page",
      })
    }
  }
}

///|
/// Check 3: Missing cross-references.
/// Pages referencing the same source files but not linking to each other.
fn check_missing_cross_references(
  wiki : @wiki_types.WikiData,
  report : LintReport,
) -> Unit {
  // Build source-file → page-id mapping
  let source_to_pages : Map[String, Array[String]] = {}
  for entry in wiki.pages {
    let (page_id, page) = (entry.0, entry.1)
    for src in page.sources {
      match source_to_pages.get(src.file) {
        Some(arr) => arr.push(page_id)
        None => source_to_pages[src.file] = [page_id]
      }
    }
  }
  // For each source file with multiple pages, check cross-links
  let checked : Map[String, Bool] = {}
  for entry in source_to_pages {
    let pages = entry.1
    if pages.length() < 2 {
      continue
    }
    for i in 0..<pages.length() {
      for j in (i + 1)..<pages.length() {
        let a = pages[i]
        let b = pages[j]
        let pair_key = a + ":" + b
        if checked.contains(pair_key) {
          continue
        }
        checked[pair_key] = true
        let a_links_b = page_links_to(wiki, a, b)
        let b_links_a = page_links_to(wiki, b, a)
        if !a_links_b && !b_links_a {
          report.add({
            severity: Info,
            check: "missing-xref",
            page_id: a,
            message: "Pages '" +
            a +
            "' and '" +
            b +
            "' share source files but don't link to each other",
            suggestion: "Add cross-references between related pages",
          })
        }
      }
    }
  }
}

///|
/// Check 4: Stale source references.
/// Pages whose sources point to files that no longer exist on disk.
/// Source paths are resolved relative to the project root derived from wiki_dir.
fn check_stale_sources(
  wiki : @wiki_types.WikiData,
  wiki_dir : String,
  report : LintReport,
) -> Unit {
  // Derive project root from wiki_dir (.indexion/wiki → project root)
  let project_root = match @config.find_project_root_from(@config.dirname(wiki_dir)) {
    Some(root) => root
    None => @config.dirname(wiki_dir)
  }
  for entry in wiki.pages {
    let (page_id, page) = (entry.0, entry.1)
    for src in page.sources {
      if src.file.length() > 0 {
        let resolved = @config.resolve_path(project_root, src.file)
        if !@fs.path_exists(resolved) {
          report.add({
            severity: Warning,
            check: "stale-source",
            page_id,
            message: "Source file not found: " + src.file,
            suggestion: "Update or remove the source reference",
          })
        }
      }
    }
  }
}

///|
/// Check 5: Empty pages.
/// Pages with no meaningful content.
fn check_empty_pages(wiki : @wiki_types.WikiData, report : LintReport) -> Unit {
  let min_content_length = 50
  for entry in wiki.pages {
    let (page_id, page) = (entry.0, entry.1)
    let content_len = count_non_whitespace(page.content)
    if content_len < min_content_length {
      report.add({
        severity: Warning,
        check: "empty",
        page_id,
        message: "Page has very little content (" +
        content_len.to_string() +
        " non-whitespace chars)",
        suggestion: "Add content or remove the page",
      })
    }
  }
}

///|
/// Check 6: Manifest-file mismatch.
/// Pages in wiki.json without corresponding .md files, or .md files not in manifest.
fn check_manifest_file_mismatch(
  wiki : @wiki_types.WikiData,
  wiki_dir : String,
  report : LintReport,
) -> Unit {
  // Check each page has a corresponding file
  for entry in wiki.pages {
    let page_id = entry.0
    let md_path = wiki_dir + "/" + page_id + ".md"
    if !@fs.path_exists(md_path) {
      report.add({
        severity: Error,
        check: "manifest-mismatch",
        page_id,
        message: "Page listed in manifest but .md file missing: " + md_path,
        suggestion: "Create the .md file or remove the page from the manifest",
      })
    }
  }
  // Note: we don't check for .md files not in manifest here because
  // we only have WikiData (not the raw directory listing).
  // The CLI layer can do this additional check.
}

///|
/// Convert a lint report to a PlanDocument for rendering.
pub fn LintReport::to_plan_document(
  self : LintReport,
) -> @plan_types.PlanDocument {
  let doc = @plan_types.PlanDocument::new("Wiki Lint Report")
  doc.set_description(
    "Structural integrity analysis of wiki content. " +
    self.total_pages.to_string() +
    " pages checked.",
  )
  doc.set_meta("labels", "wiki,lint")
  // Summary section
  let summary_items : Array[@plan_types.ListItem] = []
  summary_items.push(
    @plan_types.ListItem::simple("Total pages: " + self.total_pages.to_string()),
  )
  summary_items.push(
    @plan_types.ListItem::simple(
      "Issues found: " + self.issues.length().to_string(),
    ),
  )
  summary_items.push(
    @plan_types.ListItem::simple("Errors: " + self.error_count().to_string()),
  )
  summary_items.push(
    @plan_types.ListItem::simple(
      "Warnings: " + self.warning_count().to_string(),
    ),
  )
  doc.add_section(
    @plan_types.PlanSection::new(
      "summary",
      "Summary",
      @plan_types.SectionContent::list(summary_items),
    ),
  )
  // Group issues by check category
  let categories = [
    "broken-link", "orphan", "missing-xref", "stale-source", "empty", "manifest-mismatch",
  ]
  for category in categories {
    let items : Array[@plan_types.ChecklistItem] = []
    for issue in self.issues {
      if issue.check == category {
        items.push(
          @plan_types.ChecklistItem::with_priority(
            issue.message + " → " + issue.suggestion,
            issue.severity.priority(),
          ),
        )
      }
    }
    if items.length() > 0 {
      let title = match category {
        "broken-link" => "Broken Internal Links"
        "orphan" => "Orphan Pages"
        "missing-xref" => "Missing Cross-References"
        "stale-source" => "Stale Source References"
        "empty" => "Empty Pages"
        "manifest-mismatch" => "Manifest/File Mismatches"
        _ => category
      }
      doc.add_section(
        @plan_types.PlanSection::new(
          category,
          title,
          @plan_types.SectionContent::checklist(items),
        ),
      )
    }
  }
  doc
}

// --- Nav helpers ---

///|
/// Recursively collect all page IDs from a navigation tree item.
fn collect_nav_ids(
  item : @wiki_types.WikiNavItem,
  ids : Map[String, Bool],
) -> Unit {
  ids[item.id] = true
  for child in item.children {
    collect_nav_ids(child, ids)
  }
}

// --- String helpers ---

///|
fn find_substring(haystack : String, needle : String, from~ : Int) -> Int {
  let h_chars = haystack.to_array()
  let n_chars = needle.to_array()
  let h_len = h_chars.length()
  let n_len = n_chars.length()
  if n_len == 0 || from + n_len > h_len {
    return -1
  }
  for i in from..<=(h_len - n_len) {
    let mut matched = true
    for j in 0..<n_len {
      if h_chars[i + j] != n_chars[j] {
        matched = false
        break
      }
    }
    if matched {
      return i
    }
  }
  -1
}

///|
fn find_link_end(content : String, start : Int) -> Int {
  let chars = content.to_array()
  let len = chars.length()
  let mut i = start
  while i < len {
    let c = chars[i]
    if c == ')' ||
      c == ']' ||
      c == ' ' ||
      c == '\n' ||
      c == '"' ||
      c == '\'' ||
      c == '`' {
      break
    }
    i += 1
  }
  i
}

///|
/// Return true if `pos` falls inside a backtick code span.
/// Counts backticks before pos on the same line; if odd, pos is inside a span.
fn is_in_code_span(content : String, pos : Int) -> Bool {
  let chars = content.to_array()
  let mut count = 0
  let mut i = pos - 1
  while i >= 0 {
    let c = chars[i]
    if c == '\n' {
      break
    }
    if c == '`' {
      count += 1
    }
    i -= 1
  }
  count % 2 == 1
}

///|
fn substring(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new()
  for i in start..<end {
    if i < chars.length() {
      buf.write_char(chars[i])
    }
  }
  buf.to_string()
}

///|
/// Count non-whitespace characters in a string.
fn count_non_whitespace(s : String) -> Int {
  let chars = s.to_array()
  let mut count = 0
  for c in chars {
    if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
      count += 1
    }
  }
  count
}

///|
fn find_char(s : String, target : Char) -> Int? {
  let chars = s.to_array()
  for i in 0..<chars.length() {
    if chars[i] == target {
      return Some(i)
    }
  }
  None
}

///|
/// Check if a page's content contains a wiki:// link to the target page ID.
/// Links inside backtick code spans are not counted.
fn page_links_to(
  wiki : @wiki_types.WikiData,
  source_id : String,
  target_id : String,
) -> Bool {
  match wiki.pages.get(source_id) {
    Some(page) => {
      let search = "wiki://" + target_id
      let content = page.content
      let mut pos = 0
      let mut found = false
      while pos < content.length() {
        let idx = find_substring(content, search, from=pos)
        if idx < 0 {
          break
        }
        if !is_in_code_span(content, idx) {
          found = true
          break
        }
        pos = idx + search.length()
      }
      found
    }
    None => false
  }
}
