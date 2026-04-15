///|
pub(all) struct SpecAlignConfig {
  subcommand : String
  spec_path : String
  impl_path : String
  specs_dir : String
  cache_dir : String
  output : String
  format : String
  spec_format : String
  algorithm : String
  threshold : Double
  direction : String
  agent : String
  fail_on : String
  incremental : Bool
  git_base : String
  watch_mode : String
  watch_interval : Int
  watch_limit : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn SpecAlignConfig::default() -> SpecAlignConfig {
  {
    subcommand: "diff",
    spec_path: "",
    impl_path: "",
    specs_dir: "",
    cache_dir: "",
    output: "",
    format: "markdown",
    spec_format: "auto",
    algorithm: "hybrid",
    threshold: 0.6,
    direction: "both",
    agent: "generic",
    fail_on: "none",
    incremental: false,
    git_base: "HEAD",
    watch_mode: "diff",
    watch_interval: 2,
    watch_limit: 0,
  }
}

///|
pub struct AlignCommitInfo {
  repo_root : String
  head : String
  short_head : String
  committed_at : Int?
  dirty : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct AlignHistoryEntry {
  generated_at : Int
  source_fingerprint : String
  summary : AlignSummary
  commit : AlignCommitInfo?
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct RequirementNode {
  id : String
  title : String
  description : String
  normative : String?
  source_format : String
  source_file : String
  source_start_line : Int
  source_end_line : Int
  criteria : Array[String]
  section_refs : Array[String]
  literals : Array[String]
  table_pairs : Array[String]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct ScenarioNode {
  id : String
  title : String
  given : Array[String]
  when_ : Array[String]
  then_ : Array[String]
  parent_req : String
  source_file : String
  source_start_line : Int
  source_end_line : Int
  section_refs : Array[String]
  literals : Array[String]
  table_pairs : Array[String]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct ImplementationNode {
  id : String
  name : String
  kind : String
  category : String
  file : String
  start_line : Int
  end_line : Int
  signature : String
  declaration_text : String
  doc_comment : String?
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct TraceEdge {
  requirement_id : String
  implementation_id : String
  confidence : Double
  algorithm : String
  status : String
  rank : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct AlignDiffItem {
  category : String
  requirement_id : String?
  requirement_title : String?
  implementation_id : String?
  implementation_name : String?
  confidence : Double
  previous_confidence : Double?
  reasons : Array[String]
  spec_file : String?
  spec_line : Int?
  impl_file : String?
  impl_line : Int?
  spec_excerpt : String?
  impl_excerpt : String?
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct AlignSummary {
  matched : Int
  drifted : Int
  spec_only : Int
  impl_only : Int
  conflict : Int
  shallow : Int
  total_requirements : Int
  total_implementations : Int
  total_edges : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct AlignSnapshot {
  version : String
  generated_at : Int
  config : SpecAlignConfig
  requirements : Array[RequirementNode]
  scenarios : Array[ScenarioNode]
  implementations : Array[ImplementationNode]
  trace_edges : Array[TraceEdge]
  diff_items : Array[AlignDiffItem]
  summary : AlignSummary
  file_hashes : Map[String, String]
  source_fingerprint : String
  used_specs : Array[String]
  commit : AlignCommitInfo?
  history : Array[AlignHistoryEntry]
  cache_hit : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct AlignCacheManifest {
  version : String
  generated_at : Int
  config : SpecAlignConfig
  summary : AlignSummary
  file_hashes : Map[String, String]
  source_fingerprint : String
  used_specs : Array[String]
  commit : AlignCommitInfo?
  history_count : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct AlignTraceStore {
  requirements : Array[RequirementNode]
  scenarios : Array[ScenarioNode]
  implementations : Array[ImplementationNode]
  edges : Array[TraceEdge]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct AlignDiffStore {
  items : Array[AlignDiffItem]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct AlignHistoryStore {
  entries : Array[AlignHistoryEntry]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct AlignDiffReport {
  version : String
  generated_at : Int
  config : SpecAlignConfig
  summary : AlignSummary
  items : Array[AlignDiffItem]
  used_specs : Array[String]
  source_fingerprint : String
  commit : AlignCommitInfo?
  cache_hit : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct AlignTraceReport {
  version : String
  generated_at : Int
  config : SpecAlignConfig
  summary : AlignSummary
  requirements : Array[RequirementNode]
  implementations : Array[ImplementationNode]
  edges : Array[TraceEdge]
  source_fingerprint : String
  commit : AlignCommitInfo?
  history : Array[AlignHistoryEntry]
  cache_hit : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct AlignSuggestion {
  category : String
  direction : String
  title : String
  summary : String
  spec_file : String?
  impl_file : String?
  patch : String?
  task : String?
  reasons : Array[String]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct AlignSuggestReport {
  version : String
  generated_at : Int
  config : SpecAlignConfig
  summary : AlignSummary
  suggestions : Array[AlignSuggestion]
  used_specs : Array[String]
  source_fingerprint : String
  commit : AlignCommitInfo?
  cache_hit : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub struct AlignStatusReport {
  version : String
  generated_at : Int
  config : SpecAlignConfig
  summary : AlignSummary
  status : String
  fail_on : String
  should_fail : Bool
  used_specs : Array[String]
  source_fingerprint : String
  commit : AlignCommitInfo?
  cache_hit : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)
