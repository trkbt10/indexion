///|
struct Handle {
  db : NativePersistentDB
  provider : @text_embed.TfidfEmbeddingProvider
  layout : Layout
  metadata : Metadata
  mode : OpenMode
}

///|
pub(all) struct SearchHit {
  file : CachedFile
  score : Double
}

///|
pub(all) suberror CacheError {
  Unavailable(String)
  StorageFailure(String)
  ReplayFailure(String)
  DatabaseFailure(String)
  CheckpointFailure(String)
  RecordFailure(String)
}

///|
#warnings("-unused_value")
fn CacheError::diagnostic(self : CacheError) -> String {
  match self {
    Unavailable(message) => message
    StorageFailure(message) => message
    ReplayFailure(message) => message
    DatabaseFailure(message) => message
    CheckpointFailure(message) => message
    RecordFailure(message) => message
  }
}

///|
let default_capacity : Int = 1024

///|
pub async fn open(
  config : AgentOrientConfig,
  mode : OpenMode,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> Handle raise CacheError {
  match decide_open(config, mode, provider) {
    Ready(layout) =>
      open_validated_handle(config, mode, provider, layout)
    FreshBuild(_) => rebuild_empty(config, provider)
    Unavailable(reason) =>
      raise Unavailable(reason.diagnostic())
  }
}

///|
pub async fn open_for_update(
  config : AgentOrientConfig,
  corpus_texts : Array[String],
  dim : Int,
) -> Handle raise CacheError {
  let dim_probe = @text_embed.TfidfEmbeddingProvider::new(dim)
  match decide_open(config, ReadWrite, dim_probe) {
    Ready(layout) => {
      let provider = match load_or_build_provider(config, None, dim) {
        VocabularyLoaded(provider) => provider
        VocabularyBuilt(provider) => provider
        VocabularyInvalid(_) =>
          build_provider_from_current_corpus(corpus_texts, dim)
      }
      open_validated_handle(
        config,
        ReadWrite,
        provider,
        layout,
      )
    }
    FreshBuild(_) => {
      let provider = build_provider_from_current_corpus(
        corpus_texts, dim,
      )
      rebuild_empty(config, provider)
    }
    Unavailable(reason) =>
      raise Unavailable(reason.diagnostic())
  }
}

///|
pub async fn rebuild_empty(
  config : AgentOrientConfig,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> Handle raise CacheError {
  let layout = layout_for(config)
  reset_database_dir(layout)
  initialize_layout_for(config, provider) catch {
    LayoutStorageError(message) =>
      raise StorageFailure(message)
  }
  let metadata = metadata_for_provider(provider)
  let db = open_persistent_db(layout, provider)
  if db.dim() != provider.dim() {
    raise DatabaseFailure(
      "orient vcdb database dimension mismatch after rebuild: found " +
      db.dim().to_string() +
      ", expected " +
      provider.dim().to_string(),
    )
  }
  { db, provider, layout, metadata, mode: ReadWrite }
}

///|
fn build_provider_from_current_corpus(
  corpus_texts : Array[String],
  dim : Int,
) -> @text_embed.TfidfEmbeddingProvider raise CacheError {
  match build_vocabulary_provider(corpus_texts, dim) {
    VocabularyBuilt(provider) => provider
    VocabularyLoaded(provider) => provider
    VocabularyInvalid(reason) =>
      raise Unavailable(reason.diagnostic())
  }
}

///|
pub async fn checkpoint(
  handle : Handle,
) -> Unit raise CacheError {
  handle.db.checkpoint() catch {
    @vcdb_storage.AsyncIOFailed(message) =>
      raise CheckpointFailure(
        "orient vcdb checkpoint failed for `" +
        handle.layout.vcdb_dir +
        "`: " +
        message,
      )
    err =>
      raise CheckpointFailure(
        "orient vcdb checkpoint failed for `" +
        handle.layout.vcdb_dir +
        "`: " +
        err.to_string(),
      )
  }
}

///|
async fn open_validated_handle(
  config : AgentOrientConfig,
  mode : OpenMode,
  provider : @text_embed.TfidfEmbeddingProvider,
  layout : Layout,
) -> Handle raise CacheError {
  let db = open_persistent_db(layout, provider)
  if db.dim() == provider.dim() {
    {
      db,
      provider,
      layout,
      metadata: metadata_for_provider(provider),
      mode,
    }
  } else {
    let message = "orient vcdb database dimension mismatch: found " +
      db.dim().to_string() +
      ", expected " +
      provider.dim().to_string()
    match mode {
      ReadWrite => rebuild_empty(config, provider)
      ReadOnly => raise Unavailable(message)
    }
  }
}

///|
async fn open_persistent_db(
  layout : Layout,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> NativePersistentDB raise CacheError {
  let wal_storage = @vcdb_storage.NativeFileStorage::new(layout.vcdb_dir)
  let snapshot_storage = @vcdb_storage.NativeFileStorage::new(layout.vcdb_dir)
  @vcdb.PersistentDB::init(
    wal_storage,
    snapshot_storage,
    "",
    db_name(),
    provider.dim(),
    default_capacity,
  ) catch {
    @vcdb_storage.AsyncIOFailed(message) =>
      raise StorageFailure(
        "failed to open orient vcdb database `" +
        layout.vcdb_dir +
        "`: " +
        message,
      )
    err =>
      raise ReplayFailure(
        "failed to replay orient vcdb database `" +
        layout.vcdb_dir +
        "`: " +
        err.to_string(),
      )
  }
}

///|
async fn reset_database_dir(
  layout : Layout,
) -> Unit raise CacheError {
  let exists = @async_fs.exists(layout.vcdb_dir) catch {
    err =>
      raise StorageFailure(
        "failed to inspect orient vcdb database directory `" +
        layout.vcdb_dir +
        "`: " +
        err.to_string(),
      )
  }
  if exists {
    let is_dir = @fs.is_dir(layout.vcdb_dir) catch { _ => false }
    if is_dir {
      @async_fs.rmdir(layout.vcdb_dir, recursive=true) catch {
        err =>
          raise StorageFailure(
            "failed to reset orient vcdb database directory `" +
            layout.vcdb_dir +
            "`: " +
            err.to_string(),
          )
      }
    } else {
      @async_fs.remove(layout.vcdb_dir) catch {
        err =>
          raise StorageFailure(
            "failed to reset orient vcdb database path `" +
            layout.vcdb_dir +
            "`: " +
            err.to_string(),
          )
      }
    }
  }
  @config_paths.ensure_dir_recursive(layout.vcdb_dir)
  if !@fs.path_exists(layout.vcdb_dir) {
    raise StorageFailure(
      "failed to create orient vcdb database directory `" +
      layout.vcdb_dir +
      "`",
    )
  }
}

///|
pub fn Handle::dim(self : Handle) -> Int {
  self.db.dim()
}

///|
pub fn Handle::cache_version(self : Handle) -> String {
  self.metadata.cache_version
}

///|
pub fn Handle::provider(
  self : Handle,
) -> @text_embed.TfidfEmbeddingProvider {
  self.provider
}

///|
pub fn Handle::count(
  self : Handle,
  filter? : @vcdb_filter.FilterExpr? = None,
) -> Int {
  self.db.count_filtered(expr=filter)
}

///|
pub fn Handle::lookup_path(
  self : Handle,
  path : String,
) -> CachedFile? raise CacheError {
  let id = vector_id_for_path(path)
  match self.db.get(id) {
    Some(record) => {
      validate_existing_record_path(path, record)
      cached_file_from_record(record)
    }
    None => None
  }
}

///|
pub fn Handle::lookup_id(
  self : Handle,
  id : @vcdb_types.VectorId,
) -> CachedFile? raise CacheError {
  match self.db.get(id) {
    Some(record) =>
      match cached_file_from_record(record) {
        Some(file) =>
          if file.vector_id != id {
            raise RecordFailure(
              "orient vcdb path identity collision for `" +
              id.to_display_string() +
              "`: existing path `" +
              file.path +
              "` belongs to `" +
              file.vector_id.to_display_string() +
              "`",
            )
          } else {
            Some(file)
          }
        None => None
      }
    None => None
  }
}

///|
pub fn Handle::scan(
  self : Handle,
  filter? : @vcdb_filter.FilterExpr? = None,
  offset? : Int64? = None,
  limit? : Int = 100,
) -> Array[CachedFile] raise CacheError {
  let entries = self.db.scroll_filtered(expr=filter, offset~, limit~)
  let files : Array[CachedFile] = []
  for entry in entries {
    let (_, record) = entry
    match cached_file_from_record(record) {
      Some(file) => files.push(file)
      None => ()
    }
  }
  files
}

///|
pub fn Handle::search(
  self : Handle,
  query : Array[Double],
  k : Int,
  filter? : @vcdb_filter.FilterExpr? = None,
) -> Array[SearchHit] raise CacheError {
  validate_vector_dim(query, self.db.dim(), "search query")
  let hits = self.db.search(query, k, filter)
  let results : Array[SearchHit] = []
  for hit in hits {
    match self.lookup_id(hit.id) {
      Some(file) => results.push({ file, score: hit.score })
      None => ()
    }
  }
  results
}

///|
pub async fn Handle::upsert_brief(
  self : Handle,
  brief : LocalFileBrief,
  timestamp_ns? : Int64 = 0L,
) -> Unit raise CacheError {
  self.upsert_many([brief], timestamp_ns~)
}

///|
pub async fn Handle::upsert_many(
  self : Handle,
  briefs : Array[LocalFileBrief],
  timestamp_ns? : Int64 = 0L,
) -> Unit raise CacheError {
  validate_is_mutable(self, "upsert")
  let points : Array[(@vcdb_types.VectorId, Array[Double], @vcdb_types.Attrs)] = []
  for brief in briefs {
    let id = vector_id_for_path(brief.path)
    match self.db.get(id) {
      Some(existing) => validate_existing_record_path(brief.path, existing)
      None => ()
    }
    let vector = vector_for_brief(self.provider, brief)
    validate_vector_dim(vector, self.db.dim(), brief.path)
    points.push((id, vector, attrs_from_brief(brief)))
  }
  self.db.upsert(points, timestamp_ns) catch {
    @vcdb_storage.AsyncIOFailed(message) =>
      raise StorageFailure(
        "orient vcdb upsert failed for `" +
        self.layout.vcdb_dir +
        "`: " +
        message,
      )
    err =>
      raise DatabaseFailure(
        "orient vcdb upsert failed for `" +
        self.layout.vcdb_dir +
        "`: " +
        err.to_string(),
      )
  }
}

///|
pub async fn Handle::remove_path(
  self : Handle,
  path : String,
  timestamp_ns? : Int64 = 0L,
) -> Bool raise CacheError {
  validate_is_mutable(self, "remove")
  let id = vector_id_for_path(path)
  match self.db.get(id) {
    Some(existing) => validate_existing_record_path(path, existing)
    None => return false
  }
  self.remove_id(id, timestamp_ns~)
}

///|
pub async fn Handle::remove_id(
  self : Handle,
  id : @vcdb_types.VectorId,
  timestamp_ns? : Int64 = 0L,
) -> Bool raise CacheError {
  validate_is_mutable(self, "remove")
  match self.db.get(id) {
    Some(record) =>
      match cached_file_from_record(record) {
        Some(file) =>
          if file.vector_id != id {
            raise RecordFailure(
              "orient vcdb path identity collision for `" +
              id.to_display_string() +
              "`: existing path `" +
              file.path +
              "` belongs to `" +
              file.vector_id.to_display_string() +
              "`",
            )
          }
        None => ()
      }
    None => return false
  }
  self.db.remove(id, timestamp_ns) catch {
    @vcdb_storage.AsyncIOFailed(message) =>
      raise StorageFailure(
        "orient vcdb remove failed for `" +
        self.layout.vcdb_dir +
        "`: " +
        message,
      )
    err =>
      raise DatabaseFailure(
        "orient vcdb remove failed for `" +
        self.layout.vcdb_dir +
        "`: " +
        err.to_string(),
      )
  }
}

///|
fn validate_is_mutable(
  handle : Handle,
  operation : String,
) -> Unit raise CacheError {
  match handle.mode {
    ReadWrite => ()
    ReadOnly =>
      raise DatabaseFailure(
        "cannot " + operation + " read-only orient vcdb cache",
      )
  }
}

///|
fn cached_file_from_record(
  record : @vcdb_types.VectorRecord,
) -> CachedFile? raise CacheError {
  let id = logical_vector_id_from_record(record)
  record_to_cached_file(id, record) catch {
    PathIdentityCollision(expected, existing, vector_id) =>
      raise RecordFailure(
        "orient vcdb path identity collision for `" +
        vector_id +
        "`: expected `" +
        expected +
        "`, existing `" +
        existing +
        "`",
      )
    MissingRecordPath(vector_id) =>
      raise RecordFailure(
        "orient vcdb record `" + vector_id + "` is missing path attr",
      )
    MissingRecordAttr(attr) =>
      raise RecordFailure(
        "orient vcdb record is missing `" + attr + "` attr",
      )
    NonStringRecordAttr(attr, vector_id) =>
      raise RecordFailure(
        "orient vcdb record `" +
        vector_id +
        "` has non-string `" +
        attr +
        "` attr",
      )
  }
}

///|
fn logical_vector_id_from_record(
  record : @vcdb_types.VectorRecord,
) -> @vcdb_types.VectorId raise CacheError {
  match record.attrs.get(attr_path) {
    Some(@vcdb_types.AttrValue::String(path)) => vector_id_for_path(path)
    Some(_) =>
      raise RecordFailure(
        "orient vcdb record has non-string `" + attr_path + "` attr",
      )
    None =>
      raise RecordFailure(
        "orient vcdb record is missing `" + attr_path + "` attr",
      )
  }
}

///|
fn validate_existing_record_path(
  expected_path : String,
  record : @vcdb_types.VectorRecord,
) -> Unit raise CacheError {
  validate_record_path_for_overwrite(expected_path, record) catch {
    PathIdentityCollision(expected, existing, vector_id) =>
      raise RecordFailure(
        "orient vcdb path identity collision for `" +
        vector_id +
        "`: expected `" +
        expected +
        "`, existing `" +
        existing +
        "`",
      )
    MissingRecordPath(vector_id) =>
      raise RecordFailure(
        "orient vcdb record `" + vector_id + "` is missing path attr",
      )
    MissingRecordAttr(attr) =>
      raise RecordFailure(
        "orient vcdb record is missing `" + attr + "` attr",
      )
    NonStringRecordAttr(attr, vector_id) =>
      raise RecordFailure(
        "orient vcdb record `" +
        vector_id +
        "` has non-string `" +
        attr +
        "` attr",
      )
  }
}

///|
fn vector_for_brief(
  provider : @text_embed.TfidfEmbeddingProvider,
  brief : LocalFileBrief,
) -> Array[Double] {
  provider.embed(brief.structural_summary + "\n" + brief.summary)
}

///|
fn validate_vector_dim(
  vector : Array[Double],
  expected_dim : Int,
  label : String,
) -> Unit raise CacheError {
  if vector.length() != expected_dim {
    raise DatabaseFailure(
      "orient vcdb vector dimension mismatch for `" +
      label +
      "`: found " +
      vector.length().to_string() +
      ", expected " +
      expected_dim.to_string(),
    )
  }
}
