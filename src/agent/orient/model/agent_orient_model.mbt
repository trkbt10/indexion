///|
/// Configuration for generating an agent orientation brief and its cached map.
pub(all) struct AgentOrientConfig {
  task : String
  paths : Array[String]
  specs_dir : String
  cache_dir : String
  wiki_dir : String
  no_update : Bool
  limit : Int
  // Emit per-stage progress / timing diagnostics to stderr while the update
  // pipeline runs. The stage diagnostics are essential for diagnosing why
  // orient is slow on large repos, so the default keeps them on; set to true
  // only when piping stderr to a log would be noisy.
  quiet : Bool
  // Force a full filesystem walk on update. The default warm-cache path
  // stat()s only the paths already in the cache, which skips ~10s of walk
  // overhead on a 1900-file repo but cannot discover newly created files.
  // Pass `rescan: true` (or `--rescan` on the CLI) after adding files.
  rescan : Bool
} derive(Eq, Debug)

///|
pub fn AgentOrientConfig::default() -> AgentOrientConfig {
  {
    task: "",
    paths: ["."],
    specs_dir: "kgfs",
    cache_dir: ".indexion/cache/agent",
    wiki_dir: ".indexion/wiki",
    no_update: false,
    limit: 12,
    quiet: false,
    rescan: false,
  }
}

///|
/// Source file entry stored in the agent orientation map.
pub(all) struct AgentOrientMapFile {
  path : String
  role : String
  source_hash : String
  owner : String
  structural_summary : String
  summary : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Implementation owner profile stored in the agent orientation map.
pub(all) struct AgentOrientMapOwner {
  path : String
  source_hash : String
  files : Array[String]
  doc_sources : Array[String]
  summary : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Incremental refresh status for the agent orientation map.
pub(all) struct AgentOrientMapStatus {
  total_files : Int
  total_owners : Int
  total_doc_sources : Int
  changed_files : Array[String]
  new_files : Array[String]
  deleted_files : Array[String]
  knowledge_changed : Bool
  refreshed_owners : Array[String]
  reused_owners : Array[String]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Cached agent orientation map used for immediate owner and knowledge recall.
pub(all) struct AgentOrientMap {
  version : String
  knowledge_hash : String
  files : Array[AgentOrientMapFile]
  owners : Array[AgentOrientMapOwner]
  status : AgentOrientMapStatus
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Scored evidence row rendered in an agent orientation brief.
pub(all) struct AgentOrientEvidence {
  path : String
  kind : String
  score : Double
  matched_terms : Array[String]
  summary : String
} derive(Eq, Debug, ToJson)

///|
/// Path and reason item rendered in an agent orientation brief section.
pub(all) struct AgentOrientItem {
  path : String
  reason : String
} derive(Eq, Debug, ToJson)

///|
/// Readiness quiz item used to verify that a zero-knowledge agent understood the brief.
pub(all) struct AgentOrientQuizItem {
  question : String
  expected_answer : String
  evidence_path : String
} derive(Eq, Debug, ToJson)

///|
/// Agent orientation brief separating implementation owners from knowledge sources.
pub(all) struct AgentOrientReport {
  version : String
  task : String
  likely_owners : Array[AgentOrientItem]
  knowledge_sources : Array[AgentOrientItem]
  consumer_surfaces : Array[AgentOrientItem]
  do_not_implement_here : Array[AgentOrientItem]
  required_preflight : Array[AgentOrientItem]
  readiness_quiz : Array[AgentOrientQuizItem]
  map_status : AgentOrientMapStatus
  evidence : Array[AgentOrientEvidence]
  workflow : Array[String]
  notes : Array[String]
} derive(Eq, Debug, ToJson)
