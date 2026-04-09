///|
/// # Wiki Search Index
///
/// Builds a search index over wiki page sections using the shared
/// SearchEngine from `src/search/`. Sections are split at h2 boundaries.
///
/// ## Design
///
/// Each section is stored in vcdb with attrs[section_id_attr] = section_id.
/// This makes the index self-describing: hits from search_vector() carry
/// the section_id directly, with no external mapping file needed.
///
/// Partial updates (update_page) remove old section vectors by their vid
/// and add new ones. section_to_vid is the SoT for this reverse lookup.
///
/// The EmbeddingProvider is stored in WikiSearchIndex so that search() and
/// update_page() use the same provider as build_search_index() without
/// requiring callers to track and re-supply it.

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
} derive(ToJson, @json.FromJson)

///|
/// A search hit from the wiki index.
pub struct WikiSearchHit {
  section : WikiSection
  score : Double
} derive(ToJson)

///|
/// Wiki search index — wraps SearchEngine with wiki-specific metadata.
///
/// provider: the EmbeddingProvider used at build time.
///   Stored here so search() and update_page() use the same provider.
///
/// section_to_vid: section_id → vcdb VectorId.
///   Used for partial updates: remove old vectors before inserting new ones.
///
/// next_vid: monotonically increasing counter for new vector IDs.
///   Persisted in search-sections.json so load restores it.
pub struct WikiSearchIndex {
  engine : @search_engine.SearchEngine
  provider : @embed_config.EmbeddingProvider
  sections : Map[String, WikiSection]
  section_to_vid : Map[String, Int64]
  mut next_vid : Int64
}

///|
/// vcdb attr key used to store section_id on each vector.
pub let section_id_attr : String = "wiki_section_id"

///|
/// Build a search index from wiki pages.
/// vid is assigned monotonically from 1; next_vid is persisted for partial updates.
pub async fn build_search_index(
  pages : Map[String, @types.WikiPage],
  provider : @embed_config.EmbeddingProvider,
  registry? : @kgf_registry.KGFRegistry? = None,
) -> WikiSearchIndex raise @embed.EmbedError {
  let sections : Map[String, WikiSection] = {}
  let section_order : Array[WikiSection] = []
  for entry in pages {
    let page_id = entry.0
    let page = entry.1
    let page_file = if page.file.length() > 0 { page.file } else { page_id }
    for s in extract_sections(
      page_id,
      page.title,
      page.content,
      path=page_file,
      registry~,
    ) {
      sections[s.id] = s
      section_order.push(s)
    }
  }
  let texts : Array[String] = section_order.map(fn(s) { s.title + " " + s.content })
  let dim = @search_engine.provider_dim(provider)
  let tfidf = @text_embed.TfidfEmbeddingProvider::new(dim)
  tfidf.build_vocabulary(texts)
  let embeddings = @search_engine.embed_texts(provider, texts, tfidf)
  // BruteForce: wiki indexes have at most a few hundred pages and require
  // correct remove+add semantics for update_page. HNSW tombstones break
  // incremental updates because newly added vectors may not be reachable
  // from the existing entry point.
  let engine = @search_engine.SearchEngine::create(
    dim~,
    strategy=@embed_config.BruteForce,
  ).with_tfidf(tfidf)
  let section_to_vid : Map[String, Int64] = {}
  let mut vid : Int64 = 1L
  for i, s in section_order {
    let attrs = @search_engine.empty_attrs()
    attrs.set(section_id_attr, @vcdb_core.String(s.id))
    attrs.set("title", @vcdb_core.String(s.title))
    attrs.set("node_kind", @vcdb_core.String(if s.level == 1 { "page" } else { "section" }))
    engine.add_raw(vid, embeddings[i], attrs)
    section_to_vid[s.id] = vid
    vid += 1L
  }
  { engine, provider, sections, section_to_vid, next_vid: vid }
}

///|
/// Search the wiki index by natural language query.
pub async fn WikiSearchIndex::search(
  self : WikiSearchIndex,
  query : String,
  top_k? : Int = 10,
  min_score? : Double = 0.05,
) -> Array[WikiSearchHit] raise @embed.EmbedError {
  let tfidf = match self.engine.tfidf_provider() {
    Some(p) => p
    None => @text_embed.TfidfEmbeddingProvider::new(@search_engine.provider_dim(self.provider))
  }
  let embs = @search_engine.embed_texts(self.provider, [query], tfidf)
  let vector = embs[0]
  let raw_hits = self.engine.search_vector(vector, top_k)
  let results : Array[WikiSearchHit] = []
  for hit in raw_hits {
    if hit.score < min_score {
      continue
    }
    let section_id = match hit.attrs.get(section_id_attr) {
      Some(@vcdb_core.String(s)) => s
      _ => continue
    }
    match self.sections.get(section_id) {
      Some(section) => results.push({ section, score: hit.score })
      None => ()
    }
  }
  results
}

///|
/// Update a single page's sections in the index.
/// Removes old vectors, embeds new sections in one batch, inserts them.
/// The TF-IDF vocabulary is NOT rebuilt — queries use the existing vocabulary.
/// For vocabulary drift after many updates, rebuild with `wiki index build --full`.
pub async fn WikiSearchIndex::update_page(
  self : WikiSearchIndex,
  page_id : String,
  page_title : String,
  content : String,
  path? : String = "",
  registry? : @kgf_registry.KGFRegistry? = None,
) -> Unit raise @embed.EmbedError {
  // Remove all existing vectors for this page.
  let to_remove : Array[String] = []
  for entry in self.sections {
    if entry.1.page_id == page_id {
      to_remove.push(entry.0)
    }
  }
  for section_id in to_remove {
    match self.section_to_vid.get(section_id) {
      Some(vid) => {
        let _ = self.engine.remove(vid)
        self.section_to_vid.remove(section_id)
      }
      None => ()
    }
    self.sections.remove(section_id)
  }
  // Extract new sections and embed in one batch.
  let new_sections = extract_sections(page_id, page_title, content, path~, registry~)
  let texts : Array[String] = new_sections.map(fn(s) { s.title + " " + s.content })
  let tfidf = match self.engine.tfidf_provider() {
    Some(p) => p
    None => @text_embed.TfidfEmbeddingProvider::new(@search_engine.provider_dim(self.provider))
  }
  let embeddings = @search_engine.embed_texts(self.provider, texts, tfidf)
  for i, s in new_sections {
    let attrs = @search_engine.empty_attrs()
    attrs.set(section_id_attr, @vcdb_core.String(s.id))
    attrs.set("title", @vcdb_core.String(s.title))
    attrs.set("node_kind", @vcdb_core.String(if s.level == 1 { "page" } else { "section" }))
    let vid = self.next_vid
    self.engine.add_raw(vid, embeddings[i], attrs)
    self.section_to_vid[s.id] = vid
    self.sections[s.id] = s
    self.next_vid += 1L
  }
}

///|
/// Persist the search index to wiki_dir.
pub fn WikiSearchIndex::save(self : WikiSearchIndex, wiki_dir : String) -> Unit {
  save(self, wiki_dir)
}

///|
/// Load a persisted search index from wiki_dir.
pub fn WikiSearchIndex::load(wiki_dir : String) -> WikiSearchIndex? {
  load(wiki_dir)
}

// --- Section extraction ---

///|
/// Extract sections from page content using KGF tokenization.
pub fn extract_sections(
  page_id : String,
  page_title : String,
  content : String,
  path? : String = "",
  registry? : @kgf_registry.KGFRegistry? = None,
) -> Array[WikiSection] {
  let effective_path = if path.length() > 0 { path } else { page_id }
  let effective_reg = match registry {
    Some(r) => r
    None =>
      return [WikiSection::{ id: page_id, title: page_title, content, page_id, level: 1 }]
  }
  let spec = match effective_reg.detect_from_path(effective_path) {
    Some(lang) => effective_reg.get_spec(lang)
    None => None
  }
  let tokens = @kgf_features.tokenize_source(content, effective_path, registry)
  match tokens {
    Some(toks) =>
      extract_sections_from_document(
        @doc_structure.extract_document_sections(toks, content, spec~),
        page_id,
        page_title,
      )
    None =>
      [WikiSection::{ id: page_id, title: page_title, content, page_id, level: 1 }]
  }
}

///|
fn extract_sections_from_document(
  raw_sections : Array[@doc_structure.DocumentSection],
  page_id : String,
  page_title : String,
) -> Array[WikiSection] {
  let sections : Array[WikiSection] = []
  for idx, section in raw_sections {
    let level = section.level.unwrap_or(if idx == 0 { 1 } else { 2 })
    let id = if idx == 0 {
      page_id
    } else {
      page_id + "#" + @common.make_anchor(section.title) + "-" + (idx + 1).to_string()
    }
    sections.push(WikiSection::{
      id,
      title: if idx == 0 { page_title } else { section.title },
      content: section.content,
      page_id,
      level,
    })
  }
  sections
}
