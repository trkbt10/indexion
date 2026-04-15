///|
pub(all) struct TimestampInfo {
  epoch_seconds : Int?
  source : String
  is_dirty : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn TimestampInfo::unknown(source? : String = "unknown") -> TimestampInfo {
  { epoch_seconds: None, source, is_dirty: false }
}

///|
pub fn TimestampInfo::new(
  epoch_seconds : Int?,
  source : String,
  is_dirty : Bool,
) -> TimestampInfo {
  { epoch_seconds, source, is_dirty }
}

///|
pub(all) struct FileState {
  path : String
  file_kind : String
  spec : String
  content_hash : String
  git_time : Int?
  mtime : Int?
  git_dirty : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn FileState::new(
  path : String,
  file_kind : String,
  spec : String,
  content_hash : String,
  git_time : Int?,
  mtime : Int?,
  git_dirty : Bool,
) -> FileState {
  { path, file_kind, spec, content_hash, git_time, mtime, git_dirty }
}

///|
pub(all) struct FileTrackingConfig {
  git_preferred : Bool
  mtime_fallback : Bool
} derive(Eq, Debug)

///|
pub fn FileTrackingConfig::new(
  git_preferred : Bool,
  mtime_fallback : Bool,
) -> FileTrackingConfig {
  { git_preferred, mtime_fallback }
}

///|
pub fn FileTrackingConfig::default() -> FileTrackingConfig {
  { git_preferred: false, mtime_fallback: true }
}
