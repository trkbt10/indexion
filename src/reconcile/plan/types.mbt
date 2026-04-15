///|
/// CLI and file-backed configuration for the reconcile command.
pub(all) struct ReconcileConfig {
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
  parallel : Bool
  vocabulary_divergence_threshold : Double
} derive(Eq, Debug)

///|
/// Create a default reconcile configuration with sensible defaults.
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
    parallel: true,
    vocabulary_divergence_threshold: 0.3,
  }
}

///|
/// Timestamp metadata for a file, including epoch time, source, and dirty flag.
pub type TimestampInfo = @reconcile_tracking.TimestampInfo

///|
/// Tracked state of a source or document file for change detection.
pub type FileState = @reconcile_tracking.FileState

///|
/// A code symbol extracted from the dependency graph for reconciliation.
pub(all) struct CodeUnit {
  symbol_id : String
  name : String
  kind : String
  ns : String
  module_id : String
  module_path : String
  inline_doc : String?
  code_hash : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// A fragment of documentation extracted from a document file.
pub(all) struct DocFragment {
  id : String
  path : String
  spec : String
  kind : String
  title : String
  content : String
  preview : String
  fragment_hash : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Anchor referencing a code symbol within a reconcile candidate.
pub(all) struct CodeAnchor {
  symbol_id : String
  name : String
  kind : String
  ns : String
  module_path : String
  inline_doc : String?
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Anchor referencing a documentation fragment within a reconcile candidate.
pub(all) struct DocAnchor {
  fragment_id : String
  path : String
  spec : String
  kind : String
  title : String
  preview : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Evidence supporting the code-to-doc mapping for a candidate.
pub(all) struct MappingEvidence {
  matched_terms : Array[String]
  match_kind : String
  reason : String
  code_time : TimestampInfo
  doc_time : TimestampInfo
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// A candidate representing a code symbol that may need documentation updates.
pub(all) struct ReconcileCandidate {
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
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// A queued task for human logical review of a reconcile candidate.
pub(all) struct LogicalReviewTask {
  review_key : String
  candidate_id : String
  digest : String
  status : String
  reused : Bool
  code_anchor : CodeAnchor
  doc_anchor : DocAnchor?
  evidence : MappingEvidence
  recommended_action : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Aggregate statistics summarizing the reconcile report.
pub(all) struct ReconcileSummary {
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
  vocabulary_divergence_count : Int
  max_vocabulary_divergence : Double
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Cache hit/miss state and fingerprint info for incremental runs.
pub(all) struct CacheState {
  cache_hit : Bool
  source_fingerprint : String
  review_state_hash : String
  reused_candidates : Int
  reused_logical_reviews : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Snapshot of configuration settings stored within the reconcile report.
pub(all) struct ReconcileReportConfig {
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
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Grouped suggestion aggregating multiple candidates at module or project scope.
pub(all) struct ReconcileAggregateSuggestion {
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
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Vocabulary-level divergence between a source module and its documentation.
/// Complements symbol-level matching by comparing TF-IDF vocabulary distributions
/// to detect terms present in source code but absent from documentation.
pub(all) struct VocabularyDivergence {
  module_path : String
  doc_path : String
  cosine_distance : Double
  gap_terms : Array[String]
  source_term_count : Int
  doc_term_count : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Full reconcile report output including candidates, reviews, and summary.
pub(all) struct ReconcileReport {
  version : String
  generated_at : Int
  config : ReconcileReportConfig
  summary : ReconcileSummary
  aggregate_suggestions : Array[ReconcileAggregateSuggestion]
  candidates : Array[ReconcileCandidate]
  logical_reviews : Array[LogicalReviewTask]
  vocabulary_divergences : Array[VocabularyDivergence]
  skipped : Array[String]
  used_specs : Array[String]
  cache_state : CacheState
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// An entry in the index database tracking a record's digest and vector ID.
pub(all) struct IndexedRecordEntry {
  record_key : String
  record_kind : String
  digest : String
  vector_id : Int64
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Persisted state of a logical review decision in the manifest.
pub(all) struct LogicalReviewEntry {
  review_key : String
  candidate_id : String
  digest : String
  status : String
  verdict : String?
  updated_at : Int
  vector_id : Int64
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// User-supplied review decision for a logical review task.
pub(all) struct ReviewDecisionInput {
  review_key : String
  status : String
  verdict : String?
} derive(Eq, Debug, @json.FromJson)

///|
/// Persistent manifest tracking indexed records, reviews, and fingerprints.
pub(all) struct ReconcileManifest {
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
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Create an empty manifest with default version and zero counters.
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
