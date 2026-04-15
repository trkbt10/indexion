// DigestIndex - Main orchestration for reminiscent backtracking.
// Integrates vcdb for vector storage with function extraction and embedding.
//
// N-provider design: Engines and reverse indexes are stored in Maps keyed by
// provider key. Each provider has its own SearchEngine and vector ID space.

///|
/// Result of building/updating the index.
pub struct BuildResult {
  /// Number of functions indexed.
  mut indexed_count : Int
  /// Number of functions skipped (already up-to-date).
  mut skipped_count : Int
  /// Number of functions removed.
  mut removed_count : Int
  /// Errors encountered.
  errors : Array[String]
} derive(Eq, Debug)

///|
/// Create an empty BuildResult.
pub fn BuildResult::new() -> BuildResult {
  { indexed_count: 0, skipped_count: 0, removed_count: 0, errors: [] }
}

// TfidfEmbeddingProvider: use @text_embed.TfidfEmbeddingProvider (SoT)

///|
pub type TfidfEmbeddingProvider = @text_embed.TfidfEmbeddingProvider

///|
/// DigestIndex - Main index structure.
/// N-provider: engines and reverse indexes are keyed by provider key.
pub struct DigestIndex {
  /// Manifest for tracking state.
  mut manifest : @manifest.DigestManifest
  /// Search engines per provider (provider_key -> engine).
  engines : Map[String, @search.SearchEngine]
  /// TF-IDF embedding providers (provider_key -> provider, only for kind="tfidf").
  tfidf_providers : Map[String, TfidfEmbeddingProvider]
  /// Cached function units.
  units : Map[String, @types.FunctionUnit]
  /// Reverse index per provider (provider_key -> (vector_id -> function_id)).
  vid_to_fid : Map[String, Map[Int64, String]]
}

///|
/// Query using the first available TF-IDF provider (convenience method).
/// Used by query_by_purpose and other callers that don't specify a provider key.
pub fn DigestIndex::query(
  self : DigestIndex,
  purpose : String,
  top_k : Int,
  filter? : @vcdb_filter.FilterExpr? = None,
) -> Array[@types.QueryHit] {
  match self.first_provider_of_kind("tfidf") {
    Some(key) => self.query_local(purpose, top_k, key, filter~)
    None => []
  }
}

///|
/// Query by purpose text using a specific TF-IDF provider (synchronous).
pub fn DigestIndex::query_local(
  self : DigestIndex,
  purpose : String,
  top_k : Int,
  provider_key : String,
  filter? : @vcdb_filter.FilterExpr? = None,
) -> Array[@types.QueryHit] {
  let provider = match self.tfidf_providers.get(provider_key) {
    Some(p) => p
    None => return []
  }
  let engine = match self.engines.get(provider_key) {
    Some(e) => e
    None => return []
  }
  let reverse = match self.vid_to_fid.get(provider_key) {
    Some(m) => m
    None => return []
  }
  let vector = provider.embed(purpose)
  let hits = engine.search_vector(vector, top_k, filter~)
  let results : Array[@types.QueryHit] = []
  for hit in hits {
    let vid = hit.id.to_int64()
    match reverse.get(vid) {
      Some(fid) =>
        match self.units.get(fid) {
          Some(unit) => results.push(@types.QueryHit::new(unit, hit.score, []))
          None => ()
        }
      None => ()
    }
  }
  results
}

///|
/// Whether this index has a given provider.
pub fn DigestIndex::has_provider(self : DigestIndex, key : String) -> Bool {
  self.engines.contains(key)
}

///|
/// Get all provider keys.
pub fn DigestIndex::provider_keys(self : DigestIndex) -> Array[String] {
  let keys : Array[String] = []
  for entry in self.engines {
    keys.push(entry.0)
  }
  keys
}

///|
/// Find the first provider key of a given kind.
pub fn DigestIndex::first_provider_of_kind(
  self : DigestIndex,
  kind : String,
) -> String? {
  for entry in self.manifest.providers {
    if entry.1.kind == kind && self.engines.contains(entry.0) {
      return Some(entry.0)
    }
  }
  None
}

///|
/// Restore function units from a CodeGraph without re-embedding.
pub fn DigestIndex::restore_units_from_graph(
  self : DigestIndex,
  graph : @graph.CodeGraph,
  extract_config : @extract.ExtractConfig,
) -> Unit {
  let units = @extract.extract_function_units(graph, extract_config)
  for unit in units {
    self.units.set(unit.id(), unit)
  }
}

///|
/// Serialize index for persistence.
/// Returns (manifest_json, provider_key -> vector_db_bytes).
pub fn DigestIndex::serialize(
  self : DigestIndex,
) -> (String, Map[String, Bytes]) {
  let manifest_json = self.manifest.to_json_string()
  let db_map : Map[String, Bytes] = {}
  for entry in self.engines {
    db_map.set(entry.0, entry.1.serialize())
  }
  (manifest_json, db_map)
}

///|
/// Get statistics about the index.
pub fn DigestIndex::stats(self : DigestIndex) -> Map[String, Int] {
  let stats : Map[String, Int] = {}
  stats.set("function_count", self.manifest.functions.length())
  for entry in self.engines {
    stats.set(entry.0 + "_vector_count", entry.1.size())
    stats.set(entry.0 + "_dim", entry.1.dim())
  }
  stats
}
