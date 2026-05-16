///|
pub type AgentOrientConfig = @model.AgentOrientConfig

///|
pub type AgentOrientEvidence = @model.AgentOrientEvidence

///|
pub type AgentOrientItem = @model.AgentOrientItem

///|
pub type AgentOrientMap = @model.AgentOrientMap

///|
pub type AgentOrientMapFile = @model.AgentOrientMapFile

///|
pub type AgentOrientMapOwner = @model.AgentOrientMapOwner

///|
pub type AgentOrientMapStatus = @model.AgentOrientMapStatus

///|
pub type AgentOrientQuizItem = @model.AgentOrientQuizItem

///|
pub type AgentOrientReport = @model.AgentOrientReport

///|
/// Internal data models shared by the agent orient subpackages.
pub(all) struct LocalFileBrief {
  path : String
  role : String
  source_hash : String
  structural_summary : String
  summary : String
  structural_terms : Array[String]
  summary_terms : Array[String]
  score : Double
  matched_terms : Array[String]
  // FileSignature carry-through — populated when the brief is built from a
  // discovered signature. Zero on briefs synthesized from older caches (those
  // get re-stat'd on the next signature pass).
  mtime_ns : Int64
  size_bytes : Int64
}

///|
pub(all) struct LocalOwnerBrief {
  path : String
  score : Double
  matched_terms : Array[String]
}

///|
pub(all) struct LocalTermRank {
  term : String
  owner_docs : Int
  consumer_docs : Int
  all_docs : Int
}

///|
pub(all) struct LocalDocSource {
  path : String
  owner : String
  source_hash : String
  content : String
}

///|
pub(all) struct LocalWikiPage {
  id : String
  title : String
  file : String
  sources : Array[String]
} derive(@json.FromJson)

///|
pub(all) struct LocalWikiManifest {
  pages : Array[LocalWikiPage]
} derive(@json.FromJson)
