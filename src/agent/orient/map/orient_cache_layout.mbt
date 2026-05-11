///|
struct OrientCacheLayout {
  root_dir : String
  metadata_path : String
  vocabulary_path : String
  writer_lock_path : String
  vcdb_dir : String
  old_map_path : String
} derive(Eq, Debug)

///|
struct OrientCacheMetadata {
  cache_version : String
  schema_version : Int
  dim : Int
  created_by : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
#warnings("-unused_constructor")
enum OrientCacheOpenMode {
  OrientCacheReadWrite
  OrientCacheReadOnly
} derive(Eq, Debug)

///|
enum OrientCacheInvalidReason {
  MissingMetadata
  OldJsonLayout
  MetadataUnreadable
  CacheVersionMismatch(String)
  SchemaVersionMismatch(Int)
  MetadataDimensionMismatch(Int, Int)
  MissingVocabulary
  VocabularyUnreadable
  VocabularyDimensionMismatch(Int, Int)
} derive(Eq, Debug)

///|
enum OrientCacheOpenDecision {
  OrientCacheReady(OrientCacheLayout)
  OrientCacheFreshBuild(OrientCacheInvalidReason)
  OrientCacheUnavailable(OrientCacheInvalidReason)
} derive(Eq, Debug)

///|
priv suberror OrientCacheLayoutStorageError {
  OrientCacheLayoutStorageError(String)
}

///|
#warnings("-unused_value")
impl Show for OrientCacheOpenDecision with output(self, logger) {
  to_repr(self).output(logger)
}

///|
enum OrientCacheMetadataRead {
  MetadataLoaded(OrientCacheMetadata)
  MetadataMissing
  MetadataInvalid
} derive(Eq, Debug)

///|
fn orient_cache_version() -> String {
  "agent-orient-vcdb-v1"
}

///|
fn orient_cache_schema_version() -> Int {
  1
}

///|
fn orient_cache_created_by() -> String {
  "indexion-agent-orient"
}

///|
fn orient_cache_layout(config : AgentOrientConfig) -> OrientCacheLayout {
  let root_dir = config.cache_dir + "/orient-vcdb"
  {
    root_dir,
    metadata_path: root_dir + "/metadata.json",
    vocabulary_path: root_dir + "/tfidf-vocabulary.json",
    writer_lock_path: root_dir + "/writer.lock",
    vcdb_dir: root_dir + "/vcdb",
    old_map_path: orient_map_path(config),
  }
}

///|
fn orient_cache_metadata_for_provider(
  provider : @text_embed.TfidfEmbeddingProvider,
) -> OrientCacheMetadata {
  {
    cache_version: orient_cache_version(),
    schema_version: orient_cache_schema_version(),
    dim: provider.dim(),
    created_by: orient_cache_created_by(),
  }
}

///|
#warnings("-unused_value")
fn initialize_orient_cache_layout(
  config : AgentOrientConfig,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> Unit raise OrientCacheLayoutStorageError {
  let layout = orient_cache_layout(config)
  @config_paths.ensure_dir_recursive(layout.root_dir)
  @config_paths.ensure_dir_recursive(layout.vcdb_dir)
  @fs.write_string_to_file(
    layout.metadata_path,
    orient_cache_metadata_for_provider(provider).to_json().stringify(indent=2) +
    "\n",
  ) catch {
    @fs.IOError(msg) =>
      raise orient_cache_layout_storage_error(
        "metadata",
        layout.metadata_path,
        msg,
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
fn orient_cache_layout_storage_error(
  target : String,
  path : String,
  message : String,
) -> OrientCacheLayoutStorageError {
  OrientCacheLayoutStorageError(
    "failed to write orient vcdb " + target + " `" + path + "`: " + message,
  )
}

///|
#warnings("-unused_value")
fn read_orient_cache_metadata(
  layout : OrientCacheLayout,
) -> OrientCacheMetadata? {
  match load_orient_cache_metadata(layout) {
    MetadataLoaded(metadata) => Some(metadata)
    _ => None
  }
}

///|
fn load_orient_cache_metadata(
  layout : OrientCacheLayout,
) -> OrientCacheMetadataRead {
  if !@fs.path_exists(layout.metadata_path) {
    return MetadataMissing
  }
  let content = @fs.read_file_to_string(layout.metadata_path) catch {
    _ => return MetadataInvalid
  }
  let json = @json.parse(content) catch { _ => return MetadataInvalid }
  let metadata : OrientCacheMetadata = @json.from_json(json) catch {
    _ => return MetadataInvalid
  }
  MetadataLoaded(metadata)
}

///|
#warnings("-unused_value")
fn decide_orient_cache_open(
  config : AgentOrientConfig,
  mode : OrientCacheOpenMode,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> OrientCacheOpenDecision {
  let layout = orient_cache_layout(config)
  match orient_cache_invalid_reason(layout, provider) {
    None => OrientCacheReady(layout)
    Some(reason) =>
      match mode {
        OrientCacheReadWrite => OrientCacheFreshBuild(reason)
        OrientCacheReadOnly => OrientCacheUnavailable(reason)
      }
  }
}

///|
fn orient_cache_invalid_reason(
  layout : OrientCacheLayout,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> OrientCacheInvalidReason? {
  let metadata = match load_orient_cache_metadata(layout) {
    MetadataLoaded(metadata) => metadata
    MetadataMissing =>
      return Some(
        if @fs.path_exists(layout.old_map_path) {
          OldJsonLayout
        } else {
          MissingMetadata
        },
      )
    MetadataInvalid => return Some(MetadataUnreadable)
  }
  if metadata.cache_version != orient_cache_version() {
    return Some(CacheVersionMismatch(metadata.cache_version))
  }
  if metadata.schema_version != orient_cache_schema_version() {
    return Some(SchemaVersionMismatch(metadata.schema_version))
  }
  if metadata.dim != provider.dim() {
    return Some(MetadataDimensionMismatch(metadata.dim, provider.dim()))
  }
  validate_orient_vocabulary(layout, provider.dim())
}

///|
fn validate_orient_vocabulary(
  layout : OrientCacheLayout,
  expected_dim : Int,
) -> OrientCacheInvalidReason? {
  if !@fs.path_exists(layout.vocabulary_path) {
    return Some(MissingVocabulary)
  }
  let content = @fs.read_file_to_string(layout.vocabulary_path) catch {
    _ => return Some(VocabularyUnreadable)
  }
  let dim = match orient_vocabulary_dim_from_json(content) {
    Some(dim) => dim
    None => return Some(VocabularyUnreadable)
  }
  if dim != expected_dim {
    return Some(VocabularyDimensionMismatch(dim, expected_dim))
  }
  let provider = @text_embed.TfidfEmbeddingProvider::new(expected_dim)
  if !provider.load_from_json_string(content) {
    return Some(VocabularyUnreadable)
  }
  None
}

///|
fn orient_vocabulary_dim_from_json(content : String) -> Int? {
  let json = @json.parse(content) catch { _ => return None }
  match json {
    { "dim": Number(dim, ..), .. } => Some(dim.to_int())
    _ => None
  }
}

///|
#warnings("-unused_value")
fn OrientCacheInvalidReason::diagnostic(
  self : OrientCacheInvalidReason,
) -> String {
  match self {
    MissingMetadata => "orient vcdb cache metadata is missing"
    OldJsonLayout => "legacy orient-map.json cache layout is incompatible"
    MetadataUnreadable => "orient vcdb cache metadata is unreadable"
    CacheVersionMismatch(version) =>
      "orient vcdb cache version mismatch: " + version
    SchemaVersionMismatch(version) =>
      "orient vcdb cache schema version mismatch: " + version.to_string()
    MetadataDimensionMismatch(found, expected) =>
      "orient vcdb metadata dimension mismatch: found " +
      found.to_string() +
      ", expected " +
      expected.to_string()
    MissingVocabulary => "orient vcdb TF-IDF vocabulary is missing"
    VocabularyUnreadable => "orient vcdb TF-IDF vocabulary is unreadable"
    VocabularyDimensionMismatch(found, expected) =>
      "orient vcdb TF-IDF vocabulary dimension mismatch: found " +
      found.to_string() +
      ", expected " +
      expected.to_string()
  }
}
