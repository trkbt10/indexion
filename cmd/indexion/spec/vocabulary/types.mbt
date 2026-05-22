///|
/// Runtime configuration for `indexion spec vocabulary`.
pub(all) struct VocabularyConfig {
  source_paths : Array[String]
  target_paths : Array[String]
  specs_dir : String?
  direction : String
  format : String
  output : String
} derive(Eq, Debug)

///|
pub fn VocabularyConfig::default() -> VocabularyConfig {
  {
    source_paths: [],
    target_paths: [],
    specs_dir: None,
    direction: direction_both,
    format: output_format_text,
    output: "",
  }
}

///|
pub(all) struct VocabularyTerm {
  key : String
  kind : String
  value : String
  origin : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct VocabularyFileSummary {
  path : String
  language : String
  required_count : Int
  allowed_count : Int
  observed_count : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct VocabularyIssueAssessment {
  term : VocabularyTerm
  classification : String
  reason : String
  evidence_terms : Array[VocabularyTerm]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct VocabularyReport {
  version : String
  direction : String
  source_paths : Array[String]
  target_paths : Array[String]
  source_file_count : Int
  target_file_count : Int
  source_required_count : Int
  source_allowed_count : Int
  target_observed_count : Int
  source_files : Array[VocabularyFileSummary]
  target_files : Array[VocabularyFileSummary]
  source_required_terms : Array[VocabularyTerm]
  source_allowed_terms : Array[VocabularyTerm]
  target_terms : Array[VocabularyTerm]
  missing_source_terms : Array[VocabularyTerm]
  target_drift_terms : Array[VocabularyTerm]
  missing_source_assessments : Array[VocabularyIssueAssessment]
  target_drift_assessments : Array[VocabularyIssueAssessment]
  report_precision_candidate_count : Int
  output_noise_candidate_count : Int
  unresolved_issue_count : Int
  passed : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)
