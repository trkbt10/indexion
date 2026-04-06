// Native async embedding support using mizchi/x/http
//
// N-provider build: iterates over configured providers, generates embeddings
// for each, and stores vectors in separate engines.

///|
/// Build index using unified DigestConfig (async).
/// Iterates over all configured providers and generates embeddings for each.
pub async fn DigestIndex::build_with_config(
  self : DigestIndex,
  graph : @graph.CodeGraph,
  digest_config : @config.DigestConfig,
  file_hashes~ : Map[String, @cas_types.ContentHash]? = None,
) -> BuildResult raise @embed.EmbedError {
  let result = BuildResult::new()
  // --- Phase 1: Determine which files have changed ---
  let changed_files : Map[String, Bool] = {}
  let file_to_modules : Map[String, Array[String]] = {}
  for entry in graph.get_modules() {
    let module_id = entry.0
    let module_node = entry.1
    match module_node.file {
      Some(file_path) => {
        match file_to_modules.get(file_path) {
          Some(mods) => mods.push(module_id)
          None => file_to_modules.set(file_path, [module_id])
        }
        match file_hashes {
          Some(fh) =>
            match fh.get(file_path) {
              Some(current_hash) =>
                if !self.manifest.is_file_unchanged(file_path, current_hash) {
                  changed_files.set(file_path, true)
                }
              None => ()
            }
          None => changed_files.set(file_path, true)
        }
      }
      None => ()
    }
  }
  let changed_module_set : Map[String, Bool] = {}
  for entry in changed_files {
    match file_to_modules.get(entry.0) {
      Some(mods) =>
        for m in mods {
          changed_module_set.set(m, true)
        }
      None => ()
    }
  }
  // --- Phase 2: Extract function units ---
  let extract_config = digest_config.to_extract_config()
  let units = @extract.extract_function_units(
    graph,
    extract_config,
    file_hashes~,
  )
  for unit in units {
    self.units.set(unit.id(), unit)
  }
  // --- Phase 3: Identify stale, deleted, and unchanged functions ---
  let candidates : Array[@types.FunctionUnit] = []
  let mut unchanged_file_skip_count = 0
  for unit in units {
    if changed_module_set.contains(unit.module_id) || file_hashes is None {
      candidates.push(unit)
    } else {
      unchanged_file_skip_count += 1
    }
  }
  let stale = self.manifest.get_stale_functions(candidates)
  let current_ids : Array[String] = []
  for unit in units {
    current_ids.push(unit.id())
  }
  let (updated_manifest, removed_by_provider) = self.manifest.remove_deleted_functions(
    current_ids,
  )
  self.manifest = updated_manifest
  // Remove deleted vectors from each engine
  let mut total_removed = 0
  for entry in removed_by_provider {
    let key = entry.0
    let vids = entry.1
    match self.engines.get(key) {
      Some(engine) =>
        for vid in vids {
          let _ = engine.remove(vid)
          total_removed += 1
        }
      None => ()
    }
  }
  result.removed_count = total_removed
  // --- Phase 4: Remove stale functions' old vectors ---
  let stale_set : Map[String, Bool] = {}
  for id in stale {
    stale_set.set(id, true)
    match self.manifest.get_function(id) {
      Some(entry) =>
        for vid_entry in entry.vector_ids {
          let key = vid_entry.0
          let vid = vid_entry.1
          match self.engines.get(key) {
            Some(engine) => {
              let _ = engine.remove(vid)
              match self.vid_to_fid.get(key) {
                Some(reverse) => reverse.remove(vid)
                None => ()
              }
            }
            None => ()
          }
        }
      None => ()
    }
  }
  // --- Phase 5: Collect stale units for embedding ---
  let stale_units : Array[@types.FunctionUnit] = []
  let stale_texts : Array[String] = []
  for unit in candidates {
    if stale_set.contains(unit.id()) {
      stale_units.push(unit)
      stale_texts.push(digest_config.get_embedding_text(unit))
    } else {
      result.skipped_count += 1
    }
  }
  result.skipped_count += unchanged_file_skip_count
  if stale_texts.length() == 0 {
    self.update_file_entries(graph, file_hashes)
    return result
  }
  // --- Phase 6-7: Generate embeddings & store per provider ---
  let total = units.length()
  let stale_ratio = if total > 0 {
    stale_texts.length().to_double() / total.to_double()
  } else {
    1.0
  }
  // Collect all texts (for vocabulary rebuild) once, shared across TF-IDF providers
  let mut all_texts_cache : Array[String]? = None
  fn get_all_texts() -> Array[String] {
    match all_texts_cache {
      Some(texts) => texts
      None => {
        let texts : Array[String] = []
        for unit in units {
          texts.push(digest_config.get_embedding_text(unit))
        }
        all_texts_cache = Some(texts)
        texts
      }
    }
  }
  for provider in digest_config.providers {
    let key = provider.key
    let engine = match self.engines.get(key) {
      Some(e) => e
      None => continue // Engine not initialized — skip
    }
    let reverse = match self.vid_to_fid.get(key) {
      Some(m) => m
      None => {
        let m : Map[Int64, String] = {}
        self.vid_to_fid.set(key, m)
        m
      }
    }
    // Generate embeddings for this provider
    let embeddings : Array[Array[Double]]? = match provider.kind {
      "tfidf" =>
        match self.tfidf_providers.get(key) {
          Some(tfidf_prov) => {
            if !tfidf_prov.has_vocabulary() || stale_ratio >= 0.5 {
              tfidf_prov.build_vocabulary(get_all_texts())
            }
            let embs : Array[Array[Double]] = []
            for text in stale_texts {
              embs.push(tfidf_prov.embed(text))
            }
            Some(embs)
          }
          None => None
        }
      _ =>
        // Remote provider
        match provider.api_config {
          Some(api_config) =>
            try {
              Some(embed_with_openai_config(api_config, stale_texts))
            } catch {
              _ => {
                result.errors.push(
                  "Embedding failed for provider '" +
                  key +
                  "'; skipping",
                )
                None
              }
            }
          None => None
        }
    }
    // Store vectors
    match embeddings {
      Some(embs) =>
        for j = 0; j < stale_units.length(); j = j + 1 {
          let unit = stale_units[j]
          let vector = embs[j]
          if vector.length() == 0 {
            continue // Skip empty placeholder from failed items
          }
          let (m, vid) = self.manifest.allocate_vector_id(key)
          self.manifest = m
          let attrs = build_function_attrs(unit)
          engine.add_raw(vid, vector, attrs)
          reverse.set(vid, unit.id())
          // Update function entry vector_ids
          match self.manifest.get_function(unit.id()) {
            Some(existing) => {
              existing.vector_ids.set(key, vid)
              self.manifest = self.manifest.update_function(existing)
            }
            None => {
              let vids : Map[String, Int64] = {}
              vids.set(key, vid)
              let entry = @manifest.FunctionEntry::from_unit(unit, vids)
              self.manifest = self.manifest.update_function(entry)
            }
          }
        }
      None => ()
    }
  }
  // Ensure all stale units have a FunctionEntry even if no provider succeeded
  for j = 0; j < stale_units.length(); j = j + 1 {
    let unit = stale_units[j]
    if self.manifest.get_function(unit.id()) is None {
      let entry = @manifest.FunctionEntry::from_unit(unit, {})
      self.manifest = self.manifest.update_function(entry)
    }
  }
  result.indexed_count = stale_units.length()
  // --- Phase 8: Update file entries in manifest ---
  self.update_file_entries(graph, file_hashes)
  result
}

///|
/// Build vcdb attrs for a function unit.
fn build_function_attrs(unit : @types.FunctionUnit) -> @vcdb_core.Attrs {
  let attrs = @search.empty_attrs()
  attrs.set("node_type", @vcdb_core.String(@kgf_features.node_type_code))
  attrs.set("node_kind", @vcdb_core.String(unit.symbol.kind))
  attrs.set("name", @vcdb_core.String(unit.name()))
  attrs.set("kind", @vcdb_core.String(unit.symbol.kind))
  attrs.set("module", @vcdb_core.String(unit.module_id))
  attrs.set("depth", @vcdb_core.Int(unit.depth.to_int64()))
  attrs.set("source_hash", @vcdb_core.String(unit.source_hash.to_string()))
  attrs.set("context_hash", @vcdb_core.String(unit.context_hash.to_string()))
  match unit.symbol.doc {
    Some(doc) => attrs.set("doc", @vcdb_core.String(doc))
    None => ()
  }
  attrs
}

///|
/// Update FileEntry records in the manifest with current file content hashes.
fn DigestIndex::update_file_entries(
  self : DigestIndex,
  graph : @graph.CodeGraph,
  file_hashes : Map[String, @cas_types.ContentHash]?,
) -> Unit {
  match file_hashes {
    Some(fh) => {
      let file_functions : Map[String, Array[String]] = {}
      for entry in self.units {
        let unit = entry.1
        match graph.get_module(unit.module_id) {
          Some(m) =>
            match m.file {
              Some(fp) =>
                match file_functions.get(fp) {
                  Some(arr) => arr.push(unit.id())
                  None => file_functions.set(fp, [unit.id()])
                }
              None => ()
            }
          None => ()
        }
      }
      for entry in fh {
        let file_path = entry.0
        let content_hash = entry.1
        let func_ids = match file_functions.get(file_path) {
          Some(ids) => ids
          None => []
        }
        self.manifest = self.manifest.update_file(
          file_path,
          content_hash,
          func_ids,
        )
      }
    }
    None => ()
  }
}

///|
/// Helper: Embed a single batch of texts.
async fn embed_batch(
  config : @embed.OpenAIConfig,
  batch : Array[String],
) -> Array[Array[Double]] raise @embed.EmbedError {
  @embed.get_embeddings(config, batch)
}

///|
/// Helper: Embed texts using OpenAI-compatible API with batching and retry.
async fn embed_with_openai_config(
  api_config : @config.EmbeddingApiConfig,
  texts : Array[String],
) -> Array[Array[Double]] raise @embed.EmbedError {
  let config : @embed.OpenAIConfig = {
    api_key: api_config.api_key,
    model: api_config.model,
    base_url: api_config.base_url,
  }
  let all_embeddings : Array[Array[Double]] = Array::make(texts.length(), [])
  let initial_batch_size = 100
  let mut i = 0
  while i < texts.length() {
    let remaining = texts.length() - i
    let batch_size = if remaining < initial_batch_size {
      remaining
    } else {
      initial_batch_size
    }
    let batch : Array[String] = []
    for j = i; j < i + batch_size; j = j + 1 {
      batch.push(texts[j])
    }
    let batch_result = try {
      embed_batch(config, batch)
    } catch {
      _ => {
        if batch_size > 1 {
          let half = batch_size / 2
          let first_half : Array[String] = []
          for j = 0; j < half; j = j + 1 {
            first_half.push(batch[j])
          }
          let first_result = try { embed_batch(config, first_half) } catch {
            _ => {
              let individual : Array[Array[Double]] = []
              for j = 0; j < half; j = j + 1 {
                let single_result = try {
                  embed_batch(config, [first_half[j]])
                } catch {
                  _ => [[]]
                }
                individual.push(single_result[0])
              }
              individual
            }
          }
          let second_half : Array[String] = []
          for j = half; j < batch_size; j = j + 1 {
            second_half.push(batch[j])
          }
          let second_result = try {
            embed_batch(config, second_half)
          } catch {
            _ => {
              let individual : Array[Array[Double]] = []
              for j = 0; j < second_half.length(); j = j + 1 {
                let single_result = try {
                  embed_batch(config, [second_half[j]])
                } catch {
                  _ => [[]]
                }
                individual.push(single_result[0])
              }
              individual
            }
          }
          let combined : Array[Array[Double]] = []
          for emb in first_result {
            combined.push(emb)
          }
          for emb in second_result {
            combined.push(emb)
          }
          combined
        } else {
          [[]]
        }
      }
    }
    for k = 0; k < batch_result.length(); k = k + 1 {
      all_embeddings[i + k] = batch_result[k]
    }
    i += batch_size
  }
  all_embeddings
}

///|
/// Query using a remote embedding API (async, OpenAI-compatible).
pub async fn DigestIndex::query_api(
  self : DigestIndex,
  purpose : String,
  top_k : Int,
  provider_key : String,
  api_config : @config.EmbeddingApiConfig,
) -> Array[@types.QueryHit] raise @embed.EmbedError {
  let engine = match self.engines.get(provider_key) {
    Some(e) => e
    None => return []
  }
  let reverse = match self.vid_to_fid.get(provider_key) {
    Some(m) => m
    None => return []
  }
  let config : @embed.OpenAIConfig = {
    api_key: api_config.api_key,
    model: api_config.model,
    base_url: api_config.base_url,
  }
  let vector = @embed.get_embedding(config, purpose)
  let hits = engine.search_vector(vector, top_k)
  let results : Array[@types.QueryHit] = []
  for hit in hits {
    let vid = hit.id.to_int64()
    match reverse.get(vid) {
      Some(fid) =>
        match self.units.get(fid) {
          Some(unit) =>
            results.push(@types.QueryHit::new(unit, hit.score, []))
          None => ()
        }
      None => ()
    }
  }
  results
}

///|
/// Create DigestIndex from saved manifest and vector databases.
pub fn DigestIndex::from_manifest(
  manifest : @manifest.DigestManifest,
  db_map : Map[String, Bytes],
) -> DigestIndex {
  let engines : Map[String, @search.SearchEngine] = {}
  let tfidf_providers : Map[String, TfidfEmbeddingProvider] = {}
  let vid_to_fid : Map[String, Map[Int64, String]] = {}
  // Create engines and reverse indexes from loaded bytes
  for entry in db_map {
    let key = entry.0
    let bytes = entry.1
    let meta = manifest.providers.get(key)
    let engine = @search.SearchEngine::from_bytes(bytes)
    // If this is a TF-IDF provider, create and attach provider
    match meta {
      Some(m) =>
        if m.kind == "tfidf" {
          let prov = TfidfEmbeddingProvider::new(m.dim)
          tfidf_providers.set(key, prov)
          engines.set(key, engine.with_tfidf(prov))
        } else {
          engines.set(key, engine)
        }
      None => engines.set(key, engine)
    }
    // Build reverse index for this provider
    let reverse : Map[Int64, String] = {}
    for func_entry in manifest.functions {
      match func_entry.1.vector_ids.get(key) {
        Some(vid) => reverse.set(vid, func_entry.0)
        None => ()
      }
    }
    vid_to_fid.set(key, reverse)
  }
  { manifest, engines, tfidf_providers, units: {}, vid_to_fid }
}

///|
/// Create DigestIndex with unified config.
pub fn DigestIndex::with_config(config : @config.DigestConfig) -> DigestIndex {
  let spec_hash = @hash.to_content_hash(
    @types.FunctionHash::from_string("digest-v1"),
  )
  let provider_metas : Map[String, @manifest.ProviderMeta] = {}
  for pc in config.providers {
    let model : String? = match pc.api_config {
      Some(cfg) => Some(cfg.model)
      None => None
    }
    let base_url : String? = match pc.api_config {
      Some(cfg) => Some(cfg.base_url)
      None => None
    }
    provider_metas.set(pc.key, {
      kind: pc.kind,
      dim: pc.dim,
      model,
      base_url,
      vector_id_counter: 1L,
    })
  }
  let manifest = @manifest.DigestManifest::new(spec_hash, provider_metas)
  let strategy : @search.VcdbStrategy = match config.vcdb_strategy {
    @config.Hnsw => @search.Hnsw
    @config.Ivf => @search.Ivf
    @config.BruteForce => @search.BruteForce
  }
  let engines : Map[String, @search.SearchEngine] = {}
  let tfidf_providers : Map[String, TfidfEmbeddingProvider] = {}
  let vid_to_fid : Map[String, Map[Int64, String]] = {}
  for pc in config.providers {
    let engine = @search.SearchEngine::create(dim=pc.dim, strategy~)
    if pc.kind == "tfidf" {
      let prov = TfidfEmbeddingProvider::new(pc.dim)
      tfidf_providers.set(pc.key, prov)
      engines.set(pc.key, engine.with_tfidf(prov))
    } else {
      engines.set(pc.key, engine)
    }
    vid_to_fid.set(pc.key, {})
  }
  { manifest, engines, tfidf_providers, units: {}, vid_to_fid }
}

// --- Index store management (persistence, locking, cleanup) ---

///|
/// Acquire a build lock for the given index directory.
pub fn acquire_build_lock(index_dir : String) -> Bool {
  let lp = @config.lock_path(index_dir)
  if @fs.path_exists(lp) {
    let content = @fs.read_file_to_string(lp) catch { _ => "" }
    if content == "locked" {
      return false
    }
  }
  @app_config.ensure_dir_recursive(index_dir)
  @fs.write_string_to_file(lp, "locked") catch { _ => return false }
  true
}

///|
/// Release the build lock for the given index directory.
pub fn release_build_lock(index_dir : String) -> Unit {
  @fs.remove_file(@config.lock_path(index_dir)) catch { _ => () }
}

///|
/// Delete all index files in the given directory (for full rebuild).
pub fn delete_index_files(
  index_dir : String,
  provider_keys : Array[String],
) -> Unit {
  for name in @config.compute_index_file_names(provider_keys) {
    let path = @config.index_path(index_dir, name)
    if @fs.path_exists(path) {
      @fs.remove_file(path) catch { _ => () }
    }
  }
}

///|
/// Load an existing index from disk, or create a new one if not found.
pub fn DigestIndex::load_or_create(
  index_dir : String,
  digest_config : @config.DigestConfig,
) -> DigestIndex {
  let mp = @config.manifest_path(index_dir)
  if !@fs.path_exists(mp) {
    return DigestIndex::with_config(digest_config)
  }
  let manifest_content = @fs.read_file_to_string(mp) catch {
    _ => return DigestIndex::with_config(digest_config)
  }
  let manifest = match
    @manifest.DigestManifest::from_json_string(manifest_content) {
    Some(m) => m
    None => return DigestIndex::with_config(digest_config)
  }
  // Load vector databases for each provider in the manifest
  let db_map : Map[String, Bytes] = {}
  for entry in manifest.providers {
    let key = entry.0
    let vp = @config.vectors_db_path(index_dir, key)
    if @fs.path_exists(vp) {
      let bytes = @fs.read_file_to_bytes(vp) catch { _ => continue }
      db_map.set(key, bytes)
    }
  }
  let index = DigestIndex::from_manifest(manifest, db_map)
  // Restore TF-IDF vocabularies
  for entry in index.tfidf_providers {
    let key = entry.0
    let prov = entry.1
    let vocab_path = @config.vocabulary_json_path(index_dir, key)
    if @fs.path_exists(vocab_path) {
      let vocab_content = @fs.read_file_to_string(vocab_path) catch {
        _ => ""
      }
      if vocab_content.length() > 0 {
        let _ = prov.load_from_json_string(vocab_content)
      }
    }
  }
  index
}

///|
/// Save the index to disk.
pub fn DigestIndex::save_to_dir(
  self : DigestIndex,
  index_dir : String,
  graph : @graph.CodeGraph,
) -> Array[String] {
  let errors : Array[String] = []
  @app_config.ensure_dir_recursive(index_dir)
  let (manifest_json, db_map) = self.serialize()
  // Write manifest
  @fs.write_string_to_file(
    @config.manifest_path(index_dir),
    manifest_json,
  ) catch {
    e => errors.push("Saving manifest: " + e.to_string())
  }
  // Write vector databases per provider
  for entry in db_map {
    let key = entry.0
    let bytes = entry.1
    @fs.write_bytes_to_file(
      @config.vectors_db_path(index_dir, key),
      bytes,
    ) catch {
      e =>
        errors.push(
          "Saving vectors for '" + key + "': " + e.to_string(),
        )
    }
  }
  // Write TF-IDF vocabularies
  for entry in self.tfidf_providers {
    let key = entry.0
    let prov = entry.1
    if prov.has_vocabulary() {
      let vocab_json = prov.to_json_string()
      @fs.write_string_to_file(
        @config.vocabulary_json_path(index_dir, key),
        vocab_json,
      ) catch {
        e =>
          errors.push(
            "Saving vocabulary for '" + key + "': " + e.to_string(),
          )
      }
    }
  }
  // Write graph
  let graph_json = graph.to_json_string()
  @fs.write_string_to_file(@config.graph_path(index_dir), graph_json) catch {
    e => errors.push("Saving graph: " + e.to_string())
  }
  errors
}
