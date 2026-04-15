///|
/// # Wiki Search Index I/O
///
/// Single Source of Truth for wiki search index persistence.
/// Three files are managed together in the wiki directory:
///   - vectors.db            — serialized vcdb (vector embeddings)
///   - search-sections.json  — section metadata + vid mapping + next_vid + provider
///   - tfidf-vocabulary.json — TF-IDF vocabulary + IDF weights

///|
/// File name for the serialized vector database.
pub const VECTORS_FILE : String = "vectors.db"

///|
/// File name for the serialized section metadata (includes vid mapping).
pub const SECTIONS_FILE : String = "search-sections.json"

///|
/// File name for the TF-IDF vocabulary and IDF weights.
pub const VOCABULARY_FILE : String = "tfidf-vocabulary.json"

///|
/// Persist a WikiSearchIndex to the wiki directory.
pub fn save(index : WikiSearchIndex, wiki_dir : String) -> Unit {
  // vectors.db
  let vectors_path = @config.join_path(wiki_dir, VECTORS_FILE)
  @fs.write_bytes_to_file(vectors_path, index.engine.serialize()) catch {
    e =>
      println(
        "Warning: failed to write " + VECTORS_FILE + ": " + @debug.to_string(e),
      )
  }
  // search-sections.json: provider + next_vid + entries
  let entries : Array[Json] = []
  for entry in index.sections {
    let s = entry.1
    let vid = index.section_to_vid.get(s.id).unwrap_or(0L)
    entries.push({ "section": s.to_json(), "vid": vid.to_json() })
  }
  let sections_json : Json = {
    "provider": index.provider.to_json(),
    "next_vid": index.next_vid.to_json(),
    "entries": Json::array(entries),
  }
  let sections_path = @config.join_path(wiki_dir, SECTIONS_FILE)
  @fs.write_string_to_file(sections_path, sections_json.stringify(indent=2)) catch {
    e =>
      println(
        "Warning: failed to write " + SECTIONS_FILE + ": " + @debug.to_string(e),
      )
  }
  // tfidf-vocabulary.json
  match index.engine.tfidf_provider() {
    Some(prov) => {
      let vocab_path = @config.join_path(wiki_dir, VOCABULARY_FILE)
      @fs.write_string_to_file(vocab_path, prov.to_json_string()) catch {
        e =>
          println(
            "Warning: failed to write " +
            VOCABULARY_FILE +
            ": " +
            @debug.to_string(e),
          )
      }
    }
    None => ()
  }
}

///|
/// Load a WikiSearchIndex from the wiki directory.
/// Returns None if vectors.db or search-sections.json is absent or unreadable.
pub fn load(wiki_dir : String) -> WikiSearchIndex? {
  let vectors_path = @config.join_path(wiki_dir, VECTORS_FILE)
  let sections_path = @config.join_path(wiki_dir, SECTIONS_FILE)
  if !@fs.path_exists(vectors_path) || !@fs.path_exists(sections_path) {
    return None
  }
  let bytes = @fs.read_file_to_bytes(vectors_path) catch { _ => return None }
  let base_engine = @search_engine.SearchEngine::from_bytes(bytes)
  let engine = restore_tfidf(base_engine, wiki_dir)
  let sections_text = @fs.read_file_to_string(sections_path) catch {
    _ => return None
  }
  let sections_json : Json = @json.parse(sections_text) catch {
    _ => return None
  }
  // Parse provider (defaults to TfIdf if absent — backward compat with old indexes)
  let provider : @embed_config.EmbeddingProvider = match sections_json {
    { "provider": p, .. } => @embed_config.EmbeddingProvider::from_json(p)
    _ => @embed_config.TfIdf(@embed_config.DEFAULT_TFIDF_DIM)
  }
  // Parse next_vid (Int64 serializes as JSON string in MoonBit)
  let next_vid : Int64 = match sections_json {
    { "next_vid": String(s), .. } => @string.parse_int64(s) catch { _ => 1L }
    { "next_vid": Number(n, ..), .. } => n.to_int64()
    _ => 1L
  }
  // Parse entries: [{section, vid}]
  let sections : Map[String, WikiSection] = {}
  let section_to_vid : Map[String, Int64] = {}
  match sections_json {
    { "entries": Array(arr), .. } =>
      for item in arr {
        let s : WikiSection = match item {
          { "section": s_json, .. } =>
            @json.from_json(s_json) catch {
              _ => continue
            }
          _ => continue
        }
        let vid : Int64 = match item {
          { "vid": String(vs), .. } => @string.parse_int64(vs) catch { _ => 0L }
          { "vid": Number(vn, ..), .. } => vn.to_int64()
          _ => 0L
        }
        sections[s.id] = s
        section_to_vid[s.id] = vid
      }
    _ => ()
  }
  Some(WikiSearchIndex::{ engine, provider, sections, section_to_vid, next_vid })
}

///|
/// Return true when a persisted wiki search index exists in wiki_dir.
pub fn exists(wiki_dir : String) -> Bool {
  @fs.path_exists(@config.join_path(wiki_dir, VECTORS_FILE)) &&
  @fs.path_exists(@config.join_path(wiki_dir, SECTIONS_FILE))
}

///|
/// Attempt to restore the TF-IDF provider from tfidf-vocabulary.json.
fn restore_tfidf(
  engine : @search_engine.SearchEngine,
  wiki_dir : String,
) -> @search_engine.SearchEngine {
  let vocab_path = @config.join_path(wiki_dir, VOCABULARY_FILE)
  if !@fs.path_exists(vocab_path) {
    return engine
  }
  let json_str = @fs.read_file_to_string(vocab_path) catch {
    _ => return engine
  }
  let dim = engine.dim()
  let prov = @text_embed.TfidfEmbeddingProvider::new(dim)
  if prov.load_from_json_string(json_str) {
    engine.with_tfidf(prov)
  } else {
    engine
  }
}
