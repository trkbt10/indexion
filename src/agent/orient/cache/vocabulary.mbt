///|
pub(all) enum VocabularyState {
  VocabularyLoaded(@text_embed.TfidfEmbeddingProvider)
  VocabularyBuilt(@text_embed.TfidfEmbeddingProvider)
  VocabularyInvalid(InvalidReason)
}

///|
priv enum VocabularyLoadResult {
  VocabularyLoadReady(@text_embed.TfidfEmbeddingProvider)
  VocabularyLoadInvalid(InvalidReason)
}

///|
priv struct VocabularyPayloadSummary {
  dim : Int
  vocabulary_count : Int
  idf_count : Int
}

///|
pub fn load_or_build_provider(
  config : AgentOrientConfig,
  corpus_texts : Array[String]?,
  dim : Int,
) -> VocabularyState {
  let layout = layout_for(config)
  match load_vocabulary_provider(layout, dim) {
    VocabularyLoadReady(provider) => VocabularyLoaded(provider)
    VocabularyLoadInvalid(reason) =>
      match corpus_texts {
        Some(texts) => build_vocabulary_provider(texts, dim)
        None => VocabularyInvalid(reason)
      }
  }
}

///|
pub fn persist_provider(
  config : AgentOrientConfig,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> Unit raise LayoutStorageError {
  write_vocabulary_provider(layout_for(config), provider)
}

///|
fn build_vocabulary_provider(
  corpus_texts : Array[String],
  dim : Int,
) -> VocabularyState {
  let provider = @text_embed.TfidfEmbeddingProvider::new(dim)
  provider.build_vocabulary(corpus_texts)
  if provider.has_vocabulary() {
    VocabularyBuilt(provider)
  } else {
    VocabularyInvalid(VocabularyEmpty)
  }
}

///|
fn write_vocabulary_provider(
  layout : Layout,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> Unit raise LayoutStorageError {
  @config_paths.ensure_dir_recursive(layout.root_dir)
  if !provider.has_vocabulary() {
    raise layout_storage_error_for(
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
      raise layout_storage_error_for(
        "vocabulary",
        layout.vocabulary_path,
        msg,
      )
  }
}

///|
fn validate_vocabulary_provider(
  layout : Layout,
  expected_dim : Int,
) -> InvalidReason? {
  match load_vocabulary_provider(layout, expected_dim) {
    VocabularyLoadReady(_) => None
    VocabularyLoadInvalid(reason) => Some(reason)
  }
}

///|
fn load_vocabulary_provider(
  layout : Layout,
  expected_dim : Int,
) -> VocabularyLoadResult {
  if !@fs.path_exists(layout.vocabulary_path) {
    return VocabularyLoadInvalid(MissingVocabulary)
  }
  let content = @fs.read_file_to_string(layout.vocabulary_path) catch {
    _ => return VocabularyLoadInvalid(VocabularyUnreadable)
  }
  let summary = match vocabulary_payload_summary(content) {
    Some(summary) => summary
    None => return VocabularyLoadInvalid(VocabularyUnreadable)
  }
  if summary.dim != expected_dim {
    return VocabularyLoadInvalid(
      VocabularyDimensionMismatch(summary.dim, expected_dim),
    )
  }
  if summary.vocabulary_count == 0 || summary.idf_count == 0 {
    return VocabularyLoadInvalid(VocabularyEmpty)
  }
  let provider = @text_embed.TfidfEmbeddingProvider::new(expected_dim)
  if !provider.load_from_json_string(content) {
    return VocabularyLoadInvalid(VocabularyUnreadable)
  }
  if !provider.has_vocabulary() {
    return VocabularyLoadInvalid(VocabularyEmpty)
  }
  VocabularyLoadReady(provider)
}

///|
fn vocabulary_payload_summary(
  content : String,
) -> VocabularyPayloadSummary? {
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
