///|
struct Layout {
  root_dir : String
  metadata_path : String
  vocabulary_path : String
  writer_lock_path : String
  vcdb_dir : String
  old_map_path : String
} derive(Eq, Debug)

///|
struct Metadata {
  cache_version : String
  schema_version : Int
  dim : Int
  created_by : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) enum OpenMode {
  ReadWrite
  ReadOnly
} derive(Eq, Debug)

///|
enum InvalidReason {
  MissingMetadata
  OldJsonLayout
  MetadataUnreadable
  CacheVersionMismatch(String)
  SchemaVersionMismatch(Int)
  MetadataDimensionMismatch(Int, Int)
  MissingVocabulary
  VocabularyUnreadable
  VocabularyEmpty
  VocabularyDimensionMismatch(Int, Int)
} derive(Eq, Debug)

///|
enum OpenDecision {
  Ready(Layout)
  FreshBuild(InvalidReason)
  Unavailable(InvalidReason)
} derive(Eq, Debug)

///|
pub(all) suberror LayoutStorageError {
  LayoutStorageError(String)
}

///|
#warnings("-unused_value")
impl Show for OpenDecision with output(self, logger) {
  to_repr(self).output(logger)
}

///|
enum MetadataRead {
  MetadataLoaded(Metadata)
  MetadataMissing
  MetadataInvalid
} derive(Eq, Debug)

///|
fn cache_version() -> String {
  "agent-orient-vcdb-v1"
}

///|
fn cache_schema_version() -> Int {
  1
}

///|
fn cache_created_by() -> String {
  "indexion-agent-orient"
}

///|
fn layout_for(config : AgentOrientConfig) -> Layout {
  let root_dir = config.cache_dir + "/orient-vcdb"
  {
    root_dir,
    metadata_path: root_dir + "/metadata.json",
    vocabulary_path: root_dir + "/tfidf-vocabulary.json",
    writer_lock_path: root_dir + "/writer.lock",
    vcdb_dir: root_dir + "/vcdb",
    old_map_path: @map.orient_map_path(config),
  }
}

///|
fn metadata_for_provider(
  provider : @text_embed.TfidfEmbeddingProvider,
) -> Metadata {
  {
    cache_version: cache_version(),
    schema_version: cache_schema_version(),
    dim: provider.dim(),
    created_by: cache_created_by(),
  }
}

///|
#warnings("-unused_value")
fn initialize_layout_for(
  config : AgentOrientConfig,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> Unit raise LayoutStorageError {
  let layout = layout_for(config)
  @config_paths.ensure_dir_recursive(layout.root_dir)
  @config_paths.ensure_dir_recursive(layout.vcdb_dir)
  @fs.write_string_to_file(
    layout.metadata_path,
    metadata_for_provider(provider).to_json().stringify(indent=2) + "\n",
  ) catch {
    @fs.IOError(msg) =>
      raise layout_storage_error_for("metadata", layout.metadata_path, msg)
  }
  write_vocabulary_provider(layout, provider)
}

///|
fn layout_storage_error_for(
  target : String,
  path : String,
  message : String,
) -> LayoutStorageError {
  LayoutStorageError(
    "failed to write orient vcdb " + target + " `" + path + "`: " + message,
  )
}

///|
#warnings("-unused_value")
fn read_metadata(layout : Layout) -> Metadata? {
  match load_metadata(layout) {
    MetadataLoaded(metadata) => Some(metadata)
    _ => None
  }
}

///|
fn load_metadata(layout : Layout) -> MetadataRead {
  if !@fs.path_exists(layout.metadata_path) {
    return MetadataMissing
  }
  let content = @fs.read_file_to_string(layout.metadata_path) catch {
    _ => return MetadataInvalid
  }
  let json = @json.parse(content) catch { _ => return MetadataInvalid }
  let metadata : Metadata = @json.from_json(json) catch {
    _ => return MetadataInvalid
  }
  MetadataLoaded(metadata)
}

///|
#warnings("-unused_value")
fn decide_open(
  config : AgentOrientConfig,
  mode : OpenMode,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> OpenDecision {
  let layout = layout_for(config)
  match invalid_reason_for(layout, provider) {
    None => Ready(layout)
    Some(reason) =>
      match mode {
        ReadWrite => FreshBuild(reason)
        ReadOnly => Unavailable(reason)
      }
  }
}

///|
fn invalid_reason_for(
  layout : Layout,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> InvalidReason? {
  let metadata = match load_metadata(layout) {
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
  if metadata.cache_version != cache_version() {
    return Some(CacheVersionMismatch(metadata.cache_version))
  }
  if metadata.schema_version != cache_schema_version() {
    return Some(SchemaVersionMismatch(metadata.schema_version))
  }
  if metadata.dim != provider.dim() {
    return Some(MetadataDimensionMismatch(metadata.dim, provider.dim()))
  }
  validate_vocabulary_payload(layout, provider.dim())
}

///|
fn validate_vocabulary_payload(
  layout : Layout,
  expected_dim : Int,
) -> InvalidReason? {
  validate_vocabulary_provider(layout, expected_dim)
}

///|
#warnings("-unused_value")
fn InvalidReason::diagnostic(self : InvalidReason) -> String {
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
    VocabularyEmpty => "orient vcdb TF-IDF vocabulary is empty"
    VocabularyDimensionMismatch(found, expected) =>
      "orient vcdb TF-IDF vocabulary dimension mismatch: found " +
      found.to_string() +
      ", expected " +
      expected.to_string()
  }
}
