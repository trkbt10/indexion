// Native async embedding support using mizchi/x/http

///|
/// Build index using unified DigestConfig (async).
/// Uses DigestConfig for embedding source selection and incremental updates.
pub async fn DigestIndex::build_with_config(
  self : DigestIndex,
  graph : @graph.CodeGraph,
  digest_config : @config.DigestConfig,
  file_hashes~ : Map[String, @cas_types.ContentHash]? = None,
) -> BuildResult raise @embed.EmbedError {
  let result = BuildResult::new()
  // --- Phase 1: Determine which files have changed ---
  // Build module_id -> file_path mapping and identify changed files.
  // A file is "changed" if:
  //   (a) file_hashes is not provided (conservative: treat all as changed), or
  //   (b) the file's content hash differs from what the manifest recorded, or
  //   (c) the file is not yet tracked in the manifest
  let changed_files : Map[String, Bool] = {} // file_path -> true
  let file_to_modules : Map[String, Array[String]] = {} // file_path -> [module_ids]
  for entry in graph.get_modules() {
    let module_id = entry.0
    let module_node = entry.1
    match module_node.file {
      Some(file_path) => {
        // Track file -> modules mapping
        match file_to_modules.get(file_path) {
          Some(mods) => mods.push(module_id)
          None => file_to_modules.set(file_path, [module_id])
        }
        // Check if file has changed
        match file_hashes {
          Some(fh) =>
            match fh.get(file_path) {
              Some(current_hash) =>
                if !self.manifest.is_file_unchanged(file_path, current_hash) {
                  changed_files.set(file_path, true)
                }
              None =>
                // File not in file_hashes — might be external or unsupported
                ()
            }
          None =>
            // No file hashes provided — conservatively treat all files as changed
            changed_files.set(file_path, true)
        }
      }
      None => () // External module, no file path
    }
  }
  // Build set of modules whose files have changed
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
  // --- Phase 2: Extract function units with file-content-aware hashing ---
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
  // Only functions in changed modules need hash comparison.
  // Functions in unchanged modules are definitively up-to-date because their
  // source_hash is derived from file content, and the file hasn't changed.
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
  // Handle deleted functions
  let current_ids : Array[String] = []
  for unit in units {
    current_ids.push(unit.id())
  }
  let (updated_manifest, removed_ids) = self.manifest.remove_deleted_functions(
    current_ids,
  )
  self.manifest = updated_manifest
  for vid in removed_ids {
    let _ = self.engine.remove(vid)
  }
  result.removed_count = removed_ids.length()
  // --- Phase 4: Remove stale functions' old vectors ---
  let stale_set : Map[String, Bool] = {}
  for id in stale {
    stale_set.set(id, true)
    // Remove old vector before re-indexing
    match self.manifest.get_function(id) {
      Some(entry) =>
        match entry.vector_id {
          Some(vid) => {
            let _ = self.engine.remove(vid)
            self.vid_to_fid.remove(vid)
          }
          None => ()
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
  // Add unchanged-file skips
  result.skipped_count += unchanged_file_skip_count
  if stale_texts.length() == 0 {
    // Update FileEntry even when no functions changed, to record current hashes
    self.update_file_entries(graph, file_hashes)
    return result
  }
  // --- Phase 6: Generate embeddings ---
  let all_embeddings = match digest_config.embedding_provider {
    @config.OpenAI(api_config) =>
      embed_with_openai_config(api_config, stale_texts)
    @config.TfIdf(_dim) => {
      // TF-IDF vocabulary strategy:
      // - If vocabulary already exists (loaded from persistence) and the stale
      //   ratio is low (< 50%), reuse the existing vocabulary. The top-dim terms
      //   are unlikely to change significantly from a small number of edits.
      // - Otherwise, rebuild vocabulary from all function texts. This is needed
      //   on first build or when many functions have changed (IDF shifts).
      let total = units.length()
      let stale_ratio = if total > 0 {
        stale_texts.length().to_double() / total.to_double()
      } else {
        1.0
      }
      if !self.provider.has_vocabulary() || stale_ratio >= 0.5 {
        let all_texts : Array[String] = []
        for unit in units {
          all_texts.push(digest_config.get_embedding_text(unit))
        }
        self.provider.build_vocabulary(all_texts)
      }
      let embeddings : Array[Array[Double]] = []
      for text in stale_texts {
        embeddings.push(self.provider.embed(text))
      }
      embeddings
    }
    @config.Precomputed(_file) =>
      raise @embed.ParseError(
        "Precomputed embeddings not supported in async build",
      )
  }
  // --- Phase 7: Index stale functions ---
  for j = 0; j < stale_units.length(); j = j + 1 {
    let unit = stale_units[j]
    let vector = all_embeddings[j]
    let (m, vid) = self.manifest.allocate_vector_id()
    self.manifest = m
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
    self.engine.add_raw(vid, vector, attrs)
    self.vid_to_fid.set(vid, unit.id())
    let entry = @manifest.FunctionEntry::from_unit(unit, Some(vid))
    self.manifest = self.manifest.update_function(entry)
    result.indexed_count += 1
  }
  // --- Phase 8: Update file entries in manifest ---
  self.update_file_entries(graph, file_hashes)
  result
}

///|
/// Update FileEntry records in the manifest with current file content hashes.
/// Records which functions belong to each file for future file-level invalidation.
fn DigestIndex::update_file_entries(
  self : DigestIndex,
  graph : @graph.CodeGraph,
  file_hashes : Map[String, @cas_types.ContentHash]?,
) -> Unit {
  match file_hashes {
    Some(fh) => {
      // Build file_path -> function_ids mapping from current units
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
      // Update manifest file entries
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
/// Helper: Embed a single batch of texts. Returns embeddings or raises error.
async fn embed_batch(
  config : @embed.OpenAIConfig,
  batch : Array[String],
) -> Array[Array[Double]] raise @embed.EmbedError {
  @embed.get_embeddings(config, batch)
}

///|
/// Helper: Embed texts using OpenAI-compatible API with batching and retry.
/// On batch failure, halves the batch size and retries. Falls back to
/// single-item requests as a last resort. Items that fail individually
/// are skipped (zero-vector placeholder) and the error is not propagated,
/// since the function will remain stale for the next build to retry.
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
  // Process texts in batches with exponential backoff on failure
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
    // Try the full batch first
    let batch_result = try {
      embed_batch(config, batch)
    } catch {
      _ => {
        // Full batch failed — try halving
        if batch_size > 1 {
          let half = batch_size / 2
          // First half
          let first_half : Array[String] = []
          for j = 0; j < half; j = j + 1 {
            first_half.push(batch[j])
          }
          let first_result = try { embed_batch(config, first_half) } catch {
            _ => {
              // Half batch also failed — fall back to individual items
              let individual : Array[Array[Double]] = []
              for j = 0; j < half; j = j + 1 {
                let single_result = try {
                  embed_batch(config, [first_half[j]])
                } catch {
                  _ => [[]] // Placeholder for failed item
                }
                individual.push(single_result[0])
              }
              individual
            }
          }
          // Second half
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
          // Combine halves
          let combined : Array[Array[Double]] = []
          for emb in first_result {
            combined.push(emb)
          }
          for emb in second_result {
            combined.push(emb)
          }
          combined
        } else {
          // Single item failed — return empty placeholder
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
/// Build index using native HTTP to OpenAI API (async).
/// Backwards compatible wrapper - use build_with_config for new code.
pub async fn DigestIndex::build_native(
  self : DigestIndex,
  graph : @graph.CodeGraph,
  extract_config : @extract.ExtractConfig,
  api_key : String,
) -> BuildResult raise @embed.EmbedError {
  let digest_config : @config.DigestConfig = {
    embedding_source: @config.Raw,
    embedding_provider: @config.OpenAI(@config.EmbeddingApiConfig::new(api_key)),
    vcdb_strategy: @config.Hnsw,
    include_external: extract_config.include_external,
    exclude_kinds: extract_config.exclude_kinds,
    index_dir: @config.DEFAULT_INDEX_DIR,
    llm_config: None,
  }
  self.build_with_config(graph, digest_config)
}

///|
/// Query using OpenAI-compatible embedding API (async).
pub async fn DigestIndex::query_native(
  self : DigestIndex,
  purpose : String,
  top_k : Int,
  api_config : @config.EmbeddingApiConfig,
) -> Array[@types.QueryHit] raise @embed.EmbedError {
  let config : @embed.OpenAIConfig = {
    api_key: api_config.api_key,
    model: api_config.model,
    base_url: api_config.base_url,
  }
  let vector = @embed.get_embedding(config, purpose)
  let hits = self.engine.search_vector(vector, top_k)
  let results : Array[@types.QueryHit] = []
  for hit in hits {
    let vid = hit.id.to_int64()
    match self.vid_to_fid.get(vid) {
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
/// Create DigestIndex from saved manifest (for incremental updates).
pub fn DigestIndex::from_manifest(
  manifest : @manifest.DigestManifest,
  db_bytes : Bytes,
) -> DigestIndex {
  let dim = manifest.embedding_dim
  let provider = TfidfEmbeddingProvider::new(dim)
  let engine = @search.SearchEngine::from_bytes(db_bytes).with_tfidf(provider)
  // Rebuild reverse index from manifest
  let vid_to_fid : Map[Int64, String] = {}
  for entry in manifest.functions {
    match entry.1.vector_id {
      Some(vid) => vid_to_fid.set(vid, entry.0)
      None => ()
    }
  }
  { manifest, engine, provider, units: {}, vid_to_fid }
}

///|
/// Create DigestIndex with unified config.
pub fn DigestIndex::with_config(config : @config.DigestConfig) -> DigestIndex {
  let spec_hash = @hash.to_content_hash(
    @types.FunctionHash::from_string("digest-v1"),
  )
  let provider_name = match config.embedding_provider {
    @config.TfIdf(_) => "tfidf"
    @config.OpenAI(_) => "openai"
    @config.Precomputed(_) => "precomputed"
  }
  let manifest = @manifest.DigestManifest::new(
    spec_hash,
    provider_name,
    config.embedding_dim(),
  )
  let strategy : @search.VcdbStrategy = match config.vcdb_strategy {
    @config.Hnsw => @search.Hnsw
    @config.Ivf => @search.Ivf
    @config.BruteForce => @search.BruteForce
  }
  let provider = TfidfEmbeddingProvider::new(config.embedding_dim())
  let engine = @search.SearchEngine::create(
    dim=config.embedding_dim(),
    strategy~,
  ).with_tfidf(provider)
  { manifest, engine, provider, units: {}, vid_to_fid: {} }
}

// --- Index store management (persistence, locking, cleanup) ---

// Index file constants are defined in @config (SoT).
// Use @config.index_file_names and @config.*_path() functions.


///|
/// Acquire a build lock for the given index directory.
/// Returns true if the lock was acquired, false if another build is in progress.
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
pub fn delete_index_files(index_dir : String) -> Unit {
  for name in @config.index_file_names {
    let path = @config.index_path(index_dir, name)
    if @fs.path_exists(path) {
      @fs.remove_file(path) catch { _ => () }
    }
  }
}

///|
/// Load an existing index from disk, or create a new one if not found.
/// Returns the loaded/created index. If the existing manifest is incompatible
/// (version mismatch, provider mismatch), a new index is created.
pub fn DigestIndex::load_or_create(
  index_dir : String,
  digest_config : @config.DigestConfig,
) -> DigestIndex {
  let mp = @config.manifest_path(index_dir)
  let vp = @config.vectors_path(index_dir)
  if @fs.path_exists(mp) && @fs.path_exists(vp) {
    let manifest_content = @fs.read_file_to_string(mp) catch {
      _ => return DigestIndex::with_config(digest_config)
    }
    let manifest = match
      @manifest.DigestManifest::from_json_string(manifest_content) {
      Some(m) => m
      None => return DigestIndex::with_config(digest_config)
    }
    let db_bytes = @fs.read_file_to_bytes(vp) catch {
      _ => return DigestIndex::with_config(digest_config)
    }
    let index = DigestIndex::from_manifest(manifest, db_bytes)
    // Restore TF-IDF vocabulary if available
    let vocab_path = @config.vocabulary_path(index_dir)
    if @fs.path_exists(vocab_path) {
      let vocab_content = @fs.read_file_to_string(vocab_path) catch {
        _ => ""
      }
      if vocab_content.length() > 0 {
        let _ = index.provider.load_from_json_string(vocab_content)
      }
    }
    index
  } else {
    DigestIndex::with_config(digest_config)
  }
}

///|
/// Save the index to disk (manifest, vectors, vocabulary, graph).
pub fn DigestIndex::save_to_dir(
  self : DigestIndex,
  index_dir : String,
  graph : @graph.CodeGraph,
) -> Array[String] {
  let errors : Array[String] = []
  @app_config.ensure_dir_recursive(index_dir)
  let (manifest_json, db_bytes) = self.serialize()
  @fs.write_string_to_file(@config.manifest_path(index_dir), manifest_json) catch {
    e => errors.push("Saving manifest: " + e.to_string())
  }
  @fs.write_bytes_to_file(@config.vectors_path(index_dir), db_bytes) catch {
    e => errors.push("Saving vectors: " + e.to_string())
  }
  if self.provider.has_vocabulary() {
    let vocab_json = self.provider.to_json_string()
    @fs.write_string_to_file(
      @config.vocabulary_path(index_dir),
      vocab_json,
    ) catch {
      e => errors.push("Saving vocabulary: " + e.to_string())
    }
  }
  let graph_json = graph.to_json_string()
  @fs.write_string_to_file(@config.graph_path(index_dir), graph_json) catch {
    e => errors.push("Saving graph: " + e.to_string())
  }
  errors
}
