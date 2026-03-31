///|
/// # Wiki Search Index
///
/// Builds a search index over wiki page sections using the same
/// embedding provider configuration as digest (TF-IDF or OpenAI).
/// Sections are split at h2 boundaries.

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
/// Wiki search index backed by vcdb.
pub struct WikiSearchIndex {
  db : @vcdb.VectorDB
  /// TF-IDF provider (used for local queries; None if OpenAI-only)
  tfidf_provider : @dindex.TfidfEmbeddingProvider?
  /// OpenAI config (used for remote queries; None if TF-IDF-only)
  openai_config : @dconfig.EmbeddingApiConfig?
  sections : Map[String, WikiSection]
  id_map : Map[Int, String]
}

///|
/// Build a search index from wiki pages.
/// Uses the same EmbeddingProvider as digest — TF-IDF or OpenAI.
pub async fn build_search_index(
  pages : Map[String, WikiPage],
  provider : @dconfig.EmbeddingProvider,
) -> WikiSearchIndex raise @embed.EmbedError {
  // 1. Extract sections
  let sections : Map[String, WikiSection] = {}
  for entry in pages {
    let page_id = entry.0
    let page = entry.1
    for s in extract_sections(page_id, page.title, page.content) {
      sections[s.id] = s
    }
  }
  // 2. Collect texts
  let section_ids : Array[String] = []
  let texts : Array[String] = []
  for entry in sections {
    section_ids.push(entry.0)
    let s = entry.1
    texts.push(s.title + " " + s.content)
  }
  // 3. Embed based on provider
  let dim : Int = match provider {
    @dconfig.TfIdf(d) => d
    @dconfig.OpenAI(cfg) => cfg.dim
    @dconfig.Precomputed(_) => 256
  }
  let (embeddings, tfidf_prov, openai_cfg) = match provider {
    @dconfig.TfIdf(_) => {
      let prov = @dindex.TfidfEmbeddingProvider::new(dim)
      prov.build_vocabulary(texts)
      let embs : Array[Array[Double]] = []
      for text in texts {
        embs.push(prov.embed(text))
      }
      (embs, Some(prov), None)
    }
    @dconfig.OpenAI(api_config) => {
      let embs = embed_openai_batched(api_config, texts)
      // Also build TF-IDF as fallback for local queries
      let prov = @dindex.TfidfEmbeddingProvider::new(dim)
      prov.build_vocabulary(texts)
      (embs, Some(prov), Some(api_config))
    }
    @dconfig.Precomputed(_) => {
      // Fallback to TF-IDF
      let prov = @dindex.TfidfEmbeddingProvider::new(dim)
      prov.build_vocabulary(texts)
      let embs : Array[Array[Double]] = []
      for text in texts {
        embs.push(prov.embed(text))
      }
      (embs, Some(prov), None)
    }
  }
  // 4. Store in vcdb
  let db = @vcdb.VectorDB::with_hnsw(dim)
  let id_map : Map[Int, String] = {}
  for j = 0; j < section_ids.length(); j = j + 1 {
    let section_id = section_ids[j]
    let vector = embeddings[j]
    let vid_int = j + 1
    let vid = @vcdb_core.VectorId::from_int(vid_int)
    match sections.get(section_id) {
      Some(s) => {
        let attrs = @vcdb.empty_attrs()
        attrs.set("title", @vcdb_core.String(s.title))
        attrs.set("page_id", @vcdb_core.String(s.page_id))
        attrs.set("level", @vcdb_core.String(s.level.to_string()))
        db.add(vid, vector, attrs)
        id_map[vid_int] = section_id
      }
      None => ()
    }
  }
  WikiSearchIndex::{
    db,
    tfidf_provider: tfidf_prov,
    openai_config: openai_cfg,
    sections,
    id_map,
  }
}

///|
/// Search the wiki index by natural language query.
pub async fn WikiSearchIndex::search(
  self : WikiSearchIndex,
  query : String,
  top_k? : Int = 10,
  min_score? : Double = 0.05,
) -> Array[WikiSearchHit] {
  // Embed query using available provider
  let vector = match self.openai_config {
    Some(api_config) => {
      let cfg : @embed.OpenAIConfig = {
        api_key: api_config.api_key,
        model: api_config.model,
        base_url: api_config.base_url,
      }
      let results = @embed.get_embeddings(cfg, [query]) catch {
        _ =>
          // Fallback to TF-IDF on API error
          match self.tfidf_provider {
            Some(prov) => [prov.embed(query)]
            None => return []
          }
      }
      results[0]
    }
    None =>
      match self.tfidf_provider {
        Some(prov) => prov.embed(query)
        None => return []
      }
  }
  let hits = self.db.search(vector, top_k, None)
  let results : Array[WikiSearchHit] = []
  for hit in hits {
    if hit.score < min_score {
      continue
    }
    let vid = hit.id.to_int64().to_int()
    match self.id_map.get(vid) {
      Some(section_id) =>
        match self.sections.get(section_id) {
          Some(section) =>
            results.push(WikiSearchHit::{ section, score: hit.score })
          None => ()
        }
      None => ()
    }
  }
  results
}

///|
/// Serialize the search index to disk.
pub fn WikiSearchIndex::save(self : WikiSearchIndex, wiki_dir : String) -> Unit {
  let db_bytes = self.db.serialize()
  @fs.write_bytes_to_file(wiki_dir + "/vectors.db", db_bytes) catch {
    _ => ()
  }
}

// --- OpenAI batched embedding ---

///|
async fn embed_openai_batched(
  api_config : @dconfig.EmbeddingApiConfig,
  texts : Array[String],
) -> Array[Array[Double]] raise @embed.EmbedError {
  let cfg : @embed.OpenAIConfig = {
    api_key: api_config.api_key,
    model: api_config.model,
    base_url: api_config.base_url,
  }
  let all : Array[Array[Double]] = []
  let batch_size = 100
  let mut i = 0
  while i < texts.length() {
    let batch_end = if i + batch_size < texts.length() {
      i + batch_size
    } else {
      texts.length()
    }
    let batch : Array[String] = []
    for j = i; j < batch_end; j = j + 1 {
      batch.push(texts[j])
    }
    let embs = @embed.get_embeddings(cfg, batch)
    for emb in embs {
      all.push(emb)
    }
    i = batch_end
  }
  all
}

// --- Section extraction ---

///|
fn extract_sections(
  page_id : String,
  page_title : String,
  content : String,
) -> Array[WikiSection] {
  let sections : Array[WikiSection] = []
  // Full page as a section
  sections.push(WikiSection::{
    id: page_id,
    title: page_title,
    content: strip_markdown_headings(content),
    page_id,
    level: 1,
  })
  // Split at h2 boundaries
  let lines = @common.split_lines(content)
  let mut current_title = ""
  let mut current_anchor = ""
  let buf = StringBuilder::new()
  for line in lines {
    if line.has_prefix("## ") {
      if current_title.length() > 0 {
        let section_content = buf.to_string()
        if section_content.length() > 0 {
          sections.push(WikiSection::{
            id: page_id + "#" + current_anchor,
            title: current_title,
            content: section_content,
            page_id,
            level: 2,
          })
        }
      }
      current_title = @common.substring(line, 3, line.to_array().length())
      current_anchor = @common.make_anchor(current_title)
      buf.reset()
    } else {
      buf.write_string(line)
      buf.write_string("\n")
    }
  }
  if current_title.length() > 0 {
    let section_content = buf.to_string()
    if section_content.length() > 0 {
      sections.push(WikiSection::{
        id: page_id + "#" + current_anchor,
        title: current_title,
        content: section_content,
        page_id,
        level: 2,
      })
    }
  }
  sections
}

///|
fn strip_markdown_headings(content : String) -> String {
  let lines = @common.split_lines(content)
  let buf = StringBuilder::new()
  for line in lines {
    if line.has_prefix("# ") {
      buf.write_string(@common.substring(line, 2, line.to_array().length()))
    } else if line.has_prefix("## ") {
      buf.write_string(@common.substring(line, 3, line.to_array().length()))
    } else if line.has_prefix("### ") {
      buf.write_string(@common.substring(line, 4, line.to_array().length()))
    } else {
      buf.write_string(line)
    }
    buf.write_string("\n")
  }
  buf.to_string()
}
