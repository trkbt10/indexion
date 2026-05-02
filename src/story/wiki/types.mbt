/// Type definitions for the story wiki planner.
///
/// A story wiki is a navigable knowledge base assembled from a set of
/// spec documents. The planner walks every document in the spec group
/// and proposes one wiki page per coherent narrative unit:
///
///   - one page per markdown heading section (or the whole document if
///     it has no headings)
///
/// The planner does **not** classify documents by filename, folder, or
/// any other naming convention. The user picks which documents are
/// "spec" by passing a glob; what's inside those documents — characters,
/// settings, plot acts, research notes — is irrelevant to indexion's
/// page partitioning. If the user wants per-category navigation they
/// invoke the planner once per category (one glob per category).
///
/// Where the existing `wiki/manifest` SoT expects a four-artifact
/// page identity (page_id, manifest entry, `<id>.md`, log line), the
/// planner emits `PageProposal` values that the build step turns into
/// real wiki pages on disk.

///|
/// A proposed wiki page. Carries everything `wiki/manifest::write_page`
/// needs plus the source attribution required for ingest-style staleness
/// detection later.
pub struct PageProposal {
  /// Slug used for filename and manifest id.
  id : String
  /// Human-readable page title (the heading text, or the document
  /// basename for heading-less documents).
  title : String
  /// Markdown content body.
  content : String
  /// Spec document paths the page draws from.
  sources : Array[String]
} derive(ToJson)

///|
pub fn PageProposal::new(
  id~ : String,
  title~ : String,
  content~ : String,
  sources~ : Array[String],
) -> PageProposal {
  { id, title, content, sources }
}

///|
pub fn PageProposal::get_id(self : PageProposal) -> String {
  self.id
}

///|
pub fn PageProposal::get_title(self : PageProposal) -> String {
  self.title
}

///|
pub fn PageProposal::get_content(self : PageProposal) -> String {
  self.content
}

///|
pub fn PageProposal::get_sources(self : PageProposal) -> Array[String] {
  self.sources
}

///|
/// A planner output: list of proposals plus a count of unique source
/// documents so callers can print a one-line summary without walking
/// the proposals themselves.
pub struct StoryWikiPlan {
  proposals : Array[PageProposal]
  /// Number of unique spec documents that produced at least one page.
  source_doc_count : Int
} derive(ToJson)

///|
pub fn StoryWikiPlan::get_proposals(
  self : StoryWikiPlan,
) -> Array[PageProposal] {
  self.proposals
}

///|
pub fn StoryWikiPlan::get_source_doc_count(self : StoryWikiPlan) -> Int {
  self.source_doc_count
}

///|
/// Build summary returned by the build step. Each entry mirrors a
/// proposal that was either turned into an on-disk page (`written`) or
/// skipped because a same-id page already existed in the manifest
/// (`skipped`).
pub struct BuildResult {
  written : Array[String]
  skipped : Array[String]
} derive(ToJson)

///|
pub fn BuildResult::get_written(self : BuildResult) -> Array[String] {
  self.written
}

///|
pub fn BuildResult::get_skipped(self : BuildResult) -> Array[String] {
  self.skipped
}
