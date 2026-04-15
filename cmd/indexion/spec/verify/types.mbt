///|
/// Runtime configuration for the spec verify command.
pub(all) struct VerifyConfig {
  spec_patterns : Array[String]
  target_dir : String
  /// Root directory for .indexionignore resolution.
  /// None = use target_dir; Some("") = disable ignore file loading.
  root_dir : String?
  specs_dir : String
  format : String
  focus : String
  max_candidates : Int
  output : String
} derive(Eq, Debug)

///|
/// Create a default verify configuration with sensible defaults.
pub fn VerifyConfig::default() -> VerifyConfig {
  {
    spec_patterns: [],
    target_dir: "",
    root_dir: None,
    specs_dir: "",
    format: "json",
    focus: "all",
    max_candidates: 200,
    output: "",
  }
}

///|
/// A symbol (gap term) identified in spec but missing from implementation.
/// `kind` is derived from the KGF token type (e.g., "ident", "text", "vocab").
pub(all) struct SpecSymbol {
  identifier : String
  kind : String
  context : String
  source_path : String
  source_line : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Evidence for the gap term finding.
pub(all) struct ImplEvidence {
  found_in : Array[String]
  match_kind : String
  note : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// A single verify result item.
pub(all) struct VerifyItem {
  status : String
  spec_symbol : SpecSymbol
  evidence : ImplEvidence
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Summary statistics for the verify report.
pub(all) struct VerifySummary {
  spec_files : Int
  spec_symbols : Int
  impl_files : Int
  cosine_distance : Double
  gap_count : Int
  matched : Int
  missing : Int
  dead : Int
  drift : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Snapshot of configuration stored within the verify report.
pub(all) struct VerifyReportConfig {
  spec_paths : Array[String]
  target_dir : String
  focus : String
  max_candidates : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Full verify report output.
pub(all) struct VerifyReport {
  version : String
  generated_at : Int
  config : VerifyReportConfig
  summary : VerifySummary
  items : Array[VerifyItem]
  used_specs : Array[String]
} derive(Eq, Debug, ToJson, @json.FromJson)
