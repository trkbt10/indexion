///|
pub(all) enum OrientVocabularyState {
  OrientVocabularyLoaded(@text_embed.TfidfEmbeddingProvider)
  OrientVocabularyBuilt(@text_embed.TfidfEmbeddingProvider)
  OrientVocabularyInvalid(OrientCacheInvalidReason)
}

///|
priv enum OrientVocabularyLoadResult {
  OrientVocabularyLoadReady(@text_embed.TfidfEmbeddingProvider)
  OrientVocabularyLoadInvalid(OrientCacheInvalidReason)
}

///|
priv struct OrientVocabularyPayloadSummary {
  dim : Int
  vocabulary_count : Int
  idf_count : Int
}

///|
pub fn load_or_build_provider(
  config : AgentOrientConfig,
  corpus_texts : Array[String]?,
  dim : Int,
) -> OrientVocabularyState {
  let layout = orient_cache_layout(config)
  match load_orient_vocabulary_provider(layout, dim) {
    OrientVocabularyLoadReady(provider) => OrientVocabularyLoaded(provider)
    OrientVocabularyLoadInvalid(reason) =>
      match corpus_texts {
        Some(texts) => build_orient_vocabulary_provider(texts, dim)
        None => OrientVocabularyInvalid(reason)
      }
  }
}

///|
pub fn persist_provider(
  config : AgentOrientConfig,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> Unit raise OrientCacheLayoutStorageError {
  write_orient_vocabulary_provider(orient_cache_layout(config), provider)
}

///|
fn build_orient_vocabulary_provider(
  corpus_texts : Array[String],
  dim : Int,
) -> OrientVocabularyState {
  let provider = @text_embed.TfidfEmbeddingProvider::new(dim)
  provider.build_vocabulary(corpus_texts)
  if provider.has_vocabulary() {
    OrientVocabularyBuilt(provider)
  } else {
    OrientVocabularyInvalid(VocabularyEmpty)
  }
}

///|
fn write_orient_vocabulary_provider(
  layout : OrientCacheLayout,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> Unit raise OrientCacheLayoutStorageError {
  @config_paths.ensure_dir_recursive(layout.root_dir)
  if !provider.has_vocabulary() {
    raise orient_cache_layout_storage_error(
      "vocabulary",
      layout.vocabulary_path,
      "provider vocabulary is empty",
    )
  }
  @fs.write_string_to_file(
    layout.vocabulary_path,
    provider.to_json_string() + "\n",
  ) catch {
    @fs.IOError(msg) =>
      raise orient_cache_layout_storage_error(
        "vocabulary",
        layout.vocabulary_path,
        msg,
      )
  }
}

///|
fn validate_orient_vocabulary_provider(
  layout : OrientCacheLayout,
  expected_dim : Int,
) -> OrientCacheInvalidReason? {
  match load_orient_vocabulary_provider(layout, expected_dim) {
    OrientVocabularyLoadReady(_) => None
    OrientVocabularyLoadInvalid(reason) => Some(reason)
  }
}

///|
fn load_orient_vocabulary_provider(
  layout : OrientCacheLayout,
  expected_dim : Int,
) -> OrientVocabularyLoadResult {
  if !@fs.path_exists(layout.vocabulary_path) {
    return OrientVocabularyLoadInvalid(MissingVocabulary)
  }
  let content = @fs.read_file_to_string(layout.vocabulary_path) catch {
    _ => return OrientVocabularyLoadInvalid(VocabularyUnreadable)
  }
  let summary = match orient_vocabulary_payload_summary(content) {
    Some(summary) => summary
    None => return OrientVocabularyLoadInvalid(VocabularyUnreadable)
  }
  if summary.dim != expected_dim {
    return OrientVocabularyLoadInvalid(
      VocabularyDimensionMismatch(summary.dim, expected_dim),
    )
  }
  if summary.vocabulary_count == 0 || summary.idf_count == 0 {
    return OrientVocabularyLoadInvalid(VocabularyEmpty)
  }
  let provider = @text_embed.TfidfEmbeddingProvider::new(expected_dim)
  if !provider.load_from_json_string(content) {
    return OrientVocabularyLoadInvalid(VocabularyUnreadable)
  }
  if !provider.has_vocabulary() {
    return OrientVocabularyLoadInvalid(VocabularyEmpty)
  }
  OrientVocabularyLoadReady(provider)
}

///|
fn orient_vocabulary_payload_summary(
  content : String,
) -> OrientVocabularyPayloadSummary? {
  let json = @json.parse(content) catch { _ => return None }
  match json {
    {
      "dim": Number(dim, ..),
      "vocabulary": Array(vocabulary),
      "idf": Array(idf),
      ..
    } =>
      Some({
        dim: dim.to_int(),
        vocabulary_count: vocabulary.length(),
        idf_count: idf.length(),
      })
    _ => None
  }
}
