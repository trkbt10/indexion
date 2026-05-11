///|
struct OrientCacheHandle {
  db : OrientNativePersistentDB
  provider : @text_embed.TfidfEmbeddingProvider
  layout : OrientCacheLayout
  metadata : OrientCacheMetadata
  mode : OrientCacheOpenMode
}

///|
pub(all) struct OrientCacheSearchHit {
  file : OrientCachedFile
  score : Double
}

///|
pub(all) suberror OrientCacheError {
  OrientCacheUnavailable(String)
  OrientCacheStorageFailure(String)
  OrientCacheReplayFailure(String)
  OrientCacheDatabaseFailure(String)
  OrientCacheCheckpointFailure(String)
  OrientCacheRecordFailure(String)
}

///|
#warnings("-unused_value")
fn OrientCacheError::diagnostic(self : OrientCacheError) -> String {
  match self {
    OrientCacheUnavailable(message) => message
    OrientCacheStorageFailure(message) => message
    OrientCacheReplayFailure(message) => message
    OrientCacheDatabaseFailure(message) => message
    OrientCacheCheckpointFailure(message) => message
    OrientCacheRecordFailure(message) => message
  }
}

///|
let orient_cache_default_capacity : Int = 1024

///|
pub async fn open_cache(
  config : AgentOrientConfig,
  mode : OrientCacheOpenMode,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> OrientCacheHandle raise OrientCacheError {
  match decide_orient_cache_open(config, mode, provider) {
    OrientCacheReady(layout) =>
      open_validated_orient_cache_handle(config, mode, provider, layout)
    OrientCacheFreshBuild(_) => rebuild_empty_cache(config, provider)
    OrientCacheUnavailable(reason) =>
      raise OrientCacheUnavailable(reason.diagnostic())
  }
}

///|
pub async fn rebuild_empty_cache(
  config : AgentOrientConfig,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> OrientCacheHandle raise OrientCacheError {
  let layout = orient_cache_layout(config)
  reset_orient_cache_database_dir(layout)
  initialize_orient_cache_layout(config, provider) catch {
    OrientCacheLayoutStorageError(message) =>
      raise OrientCacheStorageFailure(message)
  }
  let metadata = orient_cache_metadata_for_provider(provider)
  let db = open_orient_persistent_db(layout, provider)
  if db.dim() != provider.dim() {
    raise OrientCacheDatabaseFailure(
      "orient vcdb database dimension mismatch after rebuild: found " +
      db.dim().to_string() +
      ", expected " +
      provider.dim().to_string(),
    )
  }
  { db, provider, layout, metadata, mode: OrientCacheReadWrite }
}

///|
pub async fn checkpoint_cache(
  handle : OrientCacheHandle,
) -> Unit raise OrientCacheError {
  handle.db.checkpoint() catch {
    @vcdb_storage.AsyncIOFailed(message) =>
      raise OrientCacheCheckpointFailure(
        "orient vcdb checkpoint failed for `" +
        handle.layout.vcdb_dir +
        "`: " +
        message,
      )
    err =>
      raise OrientCacheCheckpointFailure(
        "orient vcdb checkpoint failed for `" +
        handle.layout.vcdb_dir +
        "`: " +
        err.to_string(),
      )
  }
}

///|
async fn open_validated_orient_cache_handle(
  config : AgentOrientConfig,
  mode : OrientCacheOpenMode,
  provider : @text_embed.TfidfEmbeddingProvider,
  layout : OrientCacheLayout,
) -> OrientCacheHandle raise OrientCacheError {
  let db = open_orient_persistent_db(layout, provider)
  if db.dim() == provider.dim() {
    {
      db,
      provider,
      layout,
      metadata: orient_cache_metadata_for_provider(provider),
      mode,
    }
  } else {
    let message = "orient vcdb database dimension mismatch: found " +
      db.dim().to_string() +
      ", expected " +
      provider.dim().to_string()
    match mode {
      OrientCacheReadWrite => rebuild_empty_cache(config, provider)
      OrientCacheReadOnly => raise OrientCacheUnavailable(message)
    }
  }
}

///|
async fn open_orient_persistent_db(
  layout : OrientCacheLayout,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> OrientNativePersistentDB raise OrientCacheError {
  let wal_storage = @vcdb_storage.NativeFileStorage::new(layout.vcdb_dir)
  let snapshot_storage = @vcdb_storage.NativeFileStorage::new(layout.vcdb_dir)
  @vcdb.PersistentDB::init(
    wal_storage,
    snapshot_storage,
    "",
    orient_cache_db_name(),
    provider.dim(),
    orient_cache_default_capacity,
  ) catch {
    @vcdb_storage.AsyncIOFailed(message) =>
      raise OrientCacheStorageFailure(
        "failed to open orient vcdb database `" +
        layout.vcdb_dir +
        "`: " +
        message,
      )
    err =>
      raise OrientCacheReplayFailure(
        "failed to replay orient vcdb database `" +
        layout.vcdb_dir +
        "`: " +
        err.to_string(),
      )
  }
}

///|
async fn reset_orient_cache_database_dir(
  layout : OrientCacheLayout,
) -> Unit raise OrientCacheError {
  let exists = @async_fs.exists(layout.vcdb_dir) catch {
    err =>
      raise OrientCacheStorageFailure(
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
          raise OrientCacheStorageFailure(
            "failed to reset orient vcdb database directory `" +
            layout.vcdb_dir +
            "`: " +
            err.to_string(),
          )
      }
    } else {
      @async_fs.remove(layout.vcdb_dir) catch {
        err =>
          raise OrientCacheStorageFailure(
            "failed to reset orient vcdb database path `" +
            layout.vcdb_dir +
            "`: " +
            err.to_string(),
          )
      }
    }
  }
  @async_fs.mkdir(layout.vcdb_dir, permission=0o755, recursive=true) catch {
    err =>
      raise OrientCacheStorageFailure(
        "failed to create orient vcdb database directory `" +
        layout.vcdb_dir +
        "`: " +
        err.to_string(),
      )
  }
}

///|
pub fn OrientCacheHandle::dim(self : OrientCacheHandle) -> Int {
  self.db.dim()
}

///|
pub fn OrientCacheHandle::cache_version(self : OrientCacheHandle) -> String {
  self.metadata.cache_version
}

///|
pub fn OrientCacheHandle::provider(
  self : OrientCacheHandle,
) -> @text_embed.TfidfEmbeddingProvider {
  self.provider
}

///|
pub fn OrientCacheHandle::count(
  self : OrientCacheHandle,
  filter? : @vcdb_filter.FilterExpr? = None,
) -> Int {
  self.db.count_filtered(expr=filter)
}

///|
pub fn OrientCacheHandle::lookup_path(
  self : OrientCacheHandle,
  path : String,
) -> OrientCachedFile? raise OrientCacheError {
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
pub fn OrientCacheHandle::lookup_id(
  self : OrientCacheHandle,
  id : @vcdb_types.VectorId,
) -> OrientCachedFile? raise OrientCacheError {
  match self.db.get(id) {
    Some(record) =>
      match cached_file_from_record(record) {
        Some(file) =>
          if file.vector_id != id {
            raise OrientCacheRecordFailure(
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
pub fn OrientCacheHandle::scan(
  self : OrientCacheHandle,
  filter? : @vcdb_filter.FilterExpr? = None,
  offset? : Int64? = None,
  limit? : Int = 100,
) -> Array[OrientCachedFile] raise OrientCacheError {
  let entries = self.db.scroll_filtered(expr=filter, offset~, limit~)
  let files : Array[OrientCachedFile] = []
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
pub fn OrientCacheHandle::search(
  self : OrientCacheHandle,
  query : Array[Double],
  k : Int,
  filter? : @vcdb_filter.FilterExpr? = None,
) -> Array[OrientCacheSearchHit] raise OrientCacheError {
  validate_orient_cache_vector_dim(query, self.db.dim(), "search query")
  let hits = self.db.search(query, k, filter)
  let results : Array[OrientCacheSearchHit] = []
  for hit in hits {
    match self.lookup_id(hit.id) {
      Some(file) => results.push({ file, score: hit.score })
      None => ()
    }
  }
  results
}

///|
pub async fn OrientCacheHandle::upsert_brief(
  self : OrientCacheHandle,
  brief : LocalFileBrief,
  timestamp_ns? : Int64 = 0L,
) -> Unit raise OrientCacheError {
  self.upsert_many([brief], timestamp_ns~)
}

///|
pub async fn OrientCacheHandle::upsert_many(
  self : OrientCacheHandle,
  briefs : Array[LocalFileBrief],
  timestamp_ns? : Int64 = 0L,
) -> Unit raise OrientCacheError {
  validate_cache_is_mutable(self, "upsert")
  let points : Array[(@vcdb_types.VectorId, Array[Double], @vcdb_types.Attrs)] = []
  for brief in briefs {
    let id = vector_id_for_path(brief.path)
    match self.db.get(id) {
      Some(existing) => validate_existing_record_path(brief.path, existing)
      None => ()
    }
    let vector = orient_cache_vector_for_brief(self.provider, brief)
    validate_orient_cache_vector_dim(vector, self.db.dim(), brief.path)
    points.push((id, vector, attrs_from_brief(brief)))
  }
  self.db.upsert(points, timestamp_ns) catch {
    @vcdb_storage.AsyncIOFailed(message) =>
      raise OrientCacheStorageFailure(
        "orient vcdb upsert failed for `" +
        self.layout.vcdb_dir +
        "`: " +
        message,
      )
    err =>
      raise OrientCacheDatabaseFailure(
        "orient vcdb upsert failed for `" +
        self.layout.vcdb_dir +
        "`: " +
        err.to_string(),
      )
  }
}

///|
pub async fn OrientCacheHandle::remove_path(
  self : OrientCacheHandle,
  path : String,
  timestamp_ns? : Int64 = 0L,
) -> Bool raise OrientCacheError {
  validate_cache_is_mutable(self, "remove")
  let id = vector_id_for_path(path)
  match self.db.get(id) {
    Some(existing) => validate_existing_record_path(path, existing)
    None => return false
  }
  self.remove_id(id, timestamp_ns~)
}

///|
pub async fn OrientCacheHandle::remove_id(
  self : OrientCacheHandle,
  id : @vcdb_types.VectorId,
  timestamp_ns? : Int64 = 0L,
) -> Bool raise OrientCacheError {
  validate_cache_is_mutable(self, "remove")
  match self.db.get(id) {
    Some(record) =>
      match cached_file_from_record(record) {
        Some(file) =>
          if file.vector_id != id {
            raise OrientCacheRecordFailure(
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
      raise OrientCacheStorageFailure(
        "orient vcdb remove failed for `" +
        self.layout.vcdb_dir +
        "`: " +
        message,
      )
    err =>
      raise OrientCacheDatabaseFailure(
        "orient vcdb remove failed for `" +
        self.layout.vcdb_dir +
        "`: " +
        err.to_string(),
      )
  }
}

///|
fn validate_cache_is_mutable(
  handle : OrientCacheHandle,
  operation : String,
) -> Unit raise OrientCacheError {
  match handle.mode {
    OrientCacheReadWrite => ()
    OrientCacheReadOnly =>
      raise OrientCacheDatabaseFailure(
        "cannot " + operation + " read-only orient vcdb cache",
      )
  }
}

///|
fn cached_file_from_record(
  record : @vcdb_types.VectorRecord,
) -> OrientCachedFile? raise OrientCacheError {
  let id = logical_vector_id_from_record(record)
  record_to_cached_file(id, record) catch {
    PathIdentityCollision(expected, existing, vector_id) =>
      raise OrientCacheRecordFailure(
        "orient vcdb path identity collision for `" +
        vector_id +
        "`: expected `" +
        expected +
        "`, existing `" +
        existing +
        "`",
      )
    MissingRecordPath(vector_id) =>
      raise OrientCacheRecordFailure(
        "orient vcdb record `" + vector_id + "` is missing path attr",
      )
    MissingRecordAttr(attr) =>
      raise OrientCacheRecordFailure(
        "orient vcdb record is missing `" + attr + "` attr",
      )
    NonStringRecordAttr(attr, vector_id) =>
      raise OrientCacheRecordFailure(
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
) -> @vcdb_types.VectorId raise OrientCacheError {
  match record.attrs.get(orient_attr_path) {
    Some(@vcdb_types.AttrValue::String(path)) => vector_id_for_path(path)
    Some(_) =>
      raise OrientCacheRecordFailure(
        "orient vcdb record has non-string `" + orient_attr_path + "` attr",
      )
    None =>
      raise OrientCacheRecordFailure(
        "orient vcdb record is missing `" + orient_attr_path + "` attr",
      )
  }
}

///|
fn validate_existing_record_path(
  expected_path : String,
  record : @vcdb_types.VectorRecord,
) -> Unit raise OrientCacheError {
  validate_record_path_for_overwrite(expected_path, record) catch {
    PathIdentityCollision(expected, existing, vector_id) =>
      raise OrientCacheRecordFailure(
        "orient vcdb path identity collision for `" +
        vector_id +
        "`: expected `" +
        expected +
        "`, existing `" +
        existing +
        "`",
      )
    MissingRecordPath(vector_id) =>
      raise OrientCacheRecordFailure(
        "orient vcdb record `" + vector_id + "` is missing path attr",
      )
    MissingRecordAttr(attr) =>
      raise OrientCacheRecordFailure(
        "orient vcdb record is missing `" + attr + "` attr",
      )
    NonStringRecordAttr(attr, vector_id) =>
      raise OrientCacheRecordFailure(
        "orient vcdb record `" +
        vector_id +
        "` has non-string `" +
        attr +
        "` attr",
      )
  }
}

///|
fn orient_cache_vector_for_brief(
  provider : @text_embed.TfidfEmbeddingProvider,
  brief : LocalFileBrief,
) -> Array[Double] {
  provider.embed(brief.structural_summary + "\n" + brief.summary)
}

///|
fn validate_orient_cache_vector_dim(
  vector : Array[Double],
  expected_dim : Int,
  label : String,
) -> Unit raise OrientCacheError {
  if vector.length() != expected_dim {
    raise OrientCacheDatabaseFailure(
      "orient vcdb vector dimension mismatch for `" +
      label +
      "`: found " +
      vector.length().to_string() +
      ", expected " +
      expected_dim.to_string(),
    )
  }
}
