///|
/// CLI and file-backed reconcile configuration.
pub struct ReconcileConfig {
  target_dir : String
  output : String
  format : String
  documents : @config_paths.ReconcileDocumentScope
  specs_dir : String
  index_dir : String
  config_path : String
  review_results_path : String
  threshold_seconds : Int
  max_candidates : Int
  allow_file_fallback : Bool
  git_preferred : Bool
  mtime_fallback : Bool
  logical_review_mode : String
  show_help : Bool
} derive(Eq, Show)

///|
pub fn ReconcileConfig::default() -> ReconcileConfig {
  {
    target_dir: "",
    output: "",
    format: "json",
    documents: @config_paths.resolve_reconcile_document_scope("custom"),
    specs_dir: "",
    index_dir: "",
    config_path: "",
    review_results_path: "",
    threshold_seconds: 60,
    max_candidates: 200,
    allow_file_fallback: true,
    git_preferred: false,
    mtime_fallback: true,
    logical_review_mode: "queue",
    show_help: false,
  }
}

///|
pub struct TimestampInfo {
  epoch_seconds : Int?
  source : String
  is_dirty : Bool
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub fn TimestampInfo::unknown(source? : String = "unknown") -> TimestampInfo {
  { epoch_seconds: None, source, is_dirty: false }
}

///|
pub struct FileState {
  path : String
  file_kind : String
  spec : String
  content_hash : String
  git_time : Int?
  mtime : Int?
  git_dirty : Bool
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct CodeUnit {
  symbol_id : String
  name : String
  kind : String
  ns : String
  module_id : String
  module_path : String
  inline_doc : String?
  code_hash : String
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct DocFragment {
  id : String
  path : String
  spec : String
  kind : String
  title : String
  content : String
  preview : String
  fragment_hash : String
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct CodeAnchor {
  symbol_id : String
  name : String
  kind : String
  ns : String
  module_path : String
  inline_doc : String?
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct DocAnchor {
  fragment_id : String
  path : String
  spec : String
  kind : String
  title : String
  preview : String
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct MappingEvidence {
  matched_terms : Array[String]
  match_kind : String
  reason : String
  code_time : TimestampInfo
  doc_time : TimestampInfo
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct ReconcileCandidate {
  id : String
  symbol_id : String
  status : String
  time_relation : String
  mapping_confidence : Int
  recommended_action : String
  mechanical_digest : String
  code_anchor : CodeAnchor
  doc_anchor : DocAnchor?
  evidence : MappingEvidence
  logical_review_key : String?
  logical_review_status : String
  logical_review_reused : Bool
  needs_logical_review : Bool
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct LogicalReviewTask {
  review_key : String
  candidate_id : String
  digest : String
  status : String
  reused : Bool
  code_anchor : CodeAnchor
  doc_anchor : DocAnchor?
  evidence : MappingEvidence
  recommended_action : String
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct ReconcileSummary {
  total_symbols : Int
  symbols_with_inline_doc : Int
  module_covered_symbols : Int
  total_doc_fragments : Int
  total_candidates : Int
  total_aggregate_suggestions : Int
  module_suggestions : Int
  project_suggestions : Int
  missing_doc : Int
  stale_doc : Int
  review_mapping : Int
  review_both : Int
  pending_logical_reviews : Int
  new_logical_reviews : Int
  reused_logical_reviews : Int
  completed_logical_reviews : Int
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct CacheState {
  cache_hit : Bool
  source_fingerprint : String
  review_state_hash : String
  reused_candidates : Int
  reused_logical_reviews : Int
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct ReconcileReportConfig {
  target_dir : String
  specs_dir : String
  index_dir : String
  review_results_path : String
  doc_scope : String
  doc_paths : Array[String]
  doc_specs : Array[String]
  threshold_seconds : Int
  max_candidates : Int
  allow_file_fallback : Bool
  git_preferred : Bool
  mtime_fallback : Bool
  logical_review_mode : String
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct ReconcileAggregateSuggestion {
  id : String
  scope : String
  path : String
  status : String
  recommended_action : String
  candidate_count : Int
  logical_review_count : Int
  symbol_ids : Array[String]
  symbol_names : Array[String]
  doc_paths : Array[String]
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct ReconcileReport {
  version : String
  generated_at : Int
  config : ReconcileReportConfig
  summary : ReconcileSummary
  aggregate_suggestions : Array[ReconcileAggregateSuggestion]
  candidates : Array[ReconcileCandidate]
  logical_reviews : Array[LogicalReviewTask]
  skipped : Array[String]
  used_specs : Array[String]
  cache_state : CacheState
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct IndexedRecordEntry {
  record_key : String
  record_kind : String
  digest : String
  vector_id : Int64
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct LogicalReviewEntry {
  review_key : String
  candidate_id : String
  digest : String
  status : String
  verdict : String?
  updated_at : Int
  vector_id : Int64
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub struct ReviewDecisionInput {
  review_key : String
  status : String
  verdict : String?
} derive(Eq, Show, @json.FromJson)

///|
pub struct ReconcileManifest {
  version : String
  updated_at : Int
  config_hash : String
  source_fingerprint : String
  review_state_hash : String
  report_path : String
  vector_id_counter : Int64
  files : Map[String, FileState]
  records : Map[String, IndexedRecordEntry]
  logical_reviews : Map[String, LogicalReviewEntry]
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub fn ReconcileManifest::empty() -> ReconcileManifest {
  {
    version: "reconcile-v1",
    updated_at: 0,
    config_hash: "",
    source_fingerprint: "",
    review_state_hash: "",
    report_path: "",
    vector_id_counter: 1L,
    files: {},
    records: {},
    logical_reviews: {},
  }
}
