///|
/// # Wiki Search Index
///
/// Builds a search index over wiki page sections using the shared
/// SearchEngine from `src/search/`. Sections are split at h2 boundaries.

///|
/// A searchable section extracted from a wiki page.
pub struct WikiSection {
  /// Unique ID: "{page_id}#{anchor}"
  id : String
  /// Section heading text
  title : String
  /// Full text content of the section
  content : String
  /// Page ID this section belongs to
  page_id : String
  /// Heading level (2, 3, 4), or 1 for page-level
  level : Int
} derive(ToJson)

///|
/// A search hit from the wiki index.
pub struct WikiSearchHit {
  section : WikiSection
  score : Double
} derive(ToJson)

///|
/// Wiki search index — wraps SearchEngine with wiki-specific metadata.
pub struct WikiSearchIndex {
  engine : @search_engine.SearchEngine
  sections : Map[String, WikiSection]
}

///|
/// Build a search index from wiki pages.
/// Uses the shared SearchEngine with the specified EmbeddingProvider.
pub async fn build_search_index(
  pages : Map[String, @types.WikiPage],
  provider : @dconfig.EmbeddingProvider,
) -> WikiSearchIndex raise @embed.EmbedError {
  let sections : Map[String, WikiSection] = {}
  let documents : Array[@search_engine.SearchDocument] = []
  for entry in pages {
    let page_id = entry.0
    let page = entry.1
    let page_file = if page.file.length() > 0 { page.file } else { page_id }
    for s in extract_sections(page_id, page.title, page.content, path=page_file) {
      sections[s.id] = s
      let kind_str = if s.level == 1 { "page" } else { "section" }
      let doc_attrs : Map[String, String] = {}
      doc_attrs["node_type"] = @kgf_features.node_type_document
      doc_attrs["node_kind"] = kind_str
      doc_attrs["parent"] = page_id
      documents.push({
        id: s.id,
        text: s.title + " " + s.content,
        title: s.title,
        source: page_id,
        line: 0,
        kind: kind_str,
        attrs: doc_attrs,
      })
    }
  }
  let engine = @search_engine.SearchEngine::build(documents, provider~)
  { engine, sections }
}

///|
/// Search the wiki index by natural language query.
pub async fn WikiSearchIndex::search(
  self : WikiSearchIndex,
  query : String,
  top_k? : Int = 10,
  min_score? : Double = 0.05,
) -> Array[WikiSearchHit] {
  let hits = self.engine.search(query, top_k~, min_score~)
  let results : Array[WikiSearchHit] = []
  for hit in hits {
    match self.sections.get(hit.document.id) {
      Some(section) =>
        results.push(WikiSearchHit::{ section, score: hit.score })
      None => ()
    }
  }
  results
}

///|
/// Serialize the search index to disk.
pub fn WikiSearchIndex::save(self : WikiSearchIndex, wiki_dir : String) -> Unit {
  let db_bytes = self.engine.serialize()
  @fs.write_bytes_to_file(wiki_dir + "/vectors.db", db_bytes) catch {
    _ => ()
  }
}

// --- Section extraction ---

///|
/// Extract sections from page content using KGF tokenization.
/// Falls back to loading KGF registry from default kgfs/ directory.
pub fn extract_sections(
  page_id : String,
  page_title : String,
  content : String,
  path? : String = "",
  registry? : @kgf_registry.KGFRegistry? = None,
) -> Array[WikiSection] {
  let effective_registry = match registry {
    Some(_) => registry
    None => @kgf_features.load_registry(specs_dir="kgfs", target_dir=".")
  }
  let effective_path = if path.length() > 0 { path } else { page_id }
  let effective_reg = match effective_registry {
    Some(r) => r
    None =>
      return [
        WikiSection::{
          id: page_id,
          title: page_title,
          content,
          page_id,
          level: 1,
        },
      ]
  }
  let spec = match effective_reg.detect_from_path(effective_path) {
    Some(lang) => effective_reg.get_spec(lang)
    None => None
  }
  let tokens = @kgf_features.tokenize_source(
    content, effective_path, effective_registry,
  )
  match tokens {
    Some(toks) =>
      extract_sections_from_tokens(toks, content, page_id, page_title, spec~)
    None =>
      // If no KGF spec matches, return full page as single section
      [
        WikiSection::{
          id: page_id,
          title: page_title,
          content,
          page_id,
          level: 1,
        },
      ]
  }
}

///|
/// Extract sections from KGF tokens using the shared extract_sections_from_tokens.
fn extract_sections_from_tokens(
  tokens : Array[@kgf_types.Tok],
  content : String,
  page_id : String,
  page_title : String,
  spec? : @kgf_types.KGFSpec? = None,
) -> Array[WikiSection] {
  let raw_sections = @kgf_features.extract_sections_from_tokens(
    tokens,
    content,
    page_id,
    page_title,
    spec~,
  )
  let sections : Array[WikiSection] = []
  for section in raw_sections {
    let (id, title, section_content, level) = section
    sections.push(WikiSection::{
      id,
      title,
      content: section_content,
      page_id,
      level,
    })
  }
  sections
}
