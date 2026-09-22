///|
/// Configuration for code identity auditing.
///
/// This lives in `src/identity` rather than a CLI package because the CLI is
/// only a consumer. The identity package owns the name/content relationship.
pub(all) struct IdentityAuditConfig {
  paths : Array[String]
  specs_dirs : Array[String]
  threshold : Double
  limit : Int
  include_symbols : Bool
  include_folders : Bool
} derive(Eq, Debug)

///|
pub fn IdentityAuditConfig::default() -> IdentityAuditConfig {
  {
    paths: ["."],
    specs_dirs: [],
    threshold: 0.62,
    limit: 50,
    include_symbols: true,
    include_folders: true,
  }
}

///|
/// A mechanically derived name/content drift candidate.
pub(all) struct IdentityAuditCandidate {
  kind : String
  path : String
  name : String
  expected_summary : String
  actual_summary : String
  similarity : Double
  divergence : Double
  identity_action : String
  assessment : String
  prominent_unused : Array[String]
  recommendation : String
} derive(Eq, Debug, ToJson)

///|
pub(all) struct IdentityAuditSummary {
  scanned : Int
  candidates : Int
  threshold : Double
  max_divergence : Double
} derive(Eq, Debug, ToJson)

///|
pub(all) struct IdentityAuditReport {
  version : String
  summary : IdentityAuditSummary
  candidates : Array[IdentityAuditCandidate]
  skipped : Array[String]
} derive(Eq, Debug, ToJson)
