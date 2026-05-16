///|
pub(all) struct DriftGapTerm {
  /// Sub-token value (e.g. "locale", "widget_kit_debug").
  value : String
  /// Feature kind as produced by `@kgf_tokenize.feature_kind` (`vocab`,
  /// `Ident`, etc.).
  kind : String
  /// TF-IDF weight in the source side. Higher = rarer / more salient.
  weight : Double
} derive(Eq, Debug, ToJson)

///|
/// Drift terms surfaced from one direction of comparison.
pub(all) struct DriftDirection {
  source_path : String
  target_path : String
  gap_terms : Array[DriftGapTerm]
} derive(Eq, Debug, ToJson)

///|
/// Full drift report for one file pair.
pub(all) struct DriftReport {
  version : String
  file_a : String
  file_b : String
  spec_a : String
  spec_b : String
  feature_token_count_a : Int
  feature_token_count_b : Int
  /// Cosine distance over the full feature-token bags. 0.0 = identical,
  /// 1.0 = orthogonal.
  cosine_distance : Double
  /// Drift from `file_a` toward `file_b` (terms in A absent from B).
  a_to_b : DriftDirection
  /// Drift in the reverse direction.
  b_to_a : DriftDirection
  /// Whether the configured threshold passed (None = no threshold set).
  threshold_passed : Bool?
  /// The configured cosine-distance threshold (None = no threshold set).
  threshold : Double?
} derive(Eq, Debug, ToJson)
