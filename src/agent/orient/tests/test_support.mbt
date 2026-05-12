///|
type AgentOrientConfig = @types.AgentOrientConfig

///|
type AgentOrientItem = @types.AgentOrientItem

///|
type AgentOrientMap = @types.AgentOrientMap

///|
type LocalFileBrief = @types.LocalFileBrief

///|
type LocalWikiPage = @types.LocalWikiPage

///|
type SupportedFile = @pipeline.SupportedFile

///|
fn new_local_file_brief(
  path : String,
  source_hash : String,
  structural_summary : String,
  summary : String,
  role? : String = "implementation",
  structural_terms? : Array[String] = [],
  summary_terms? : Array[String] = [],
) -> LocalFileBrief {
  @source.new_local_file_brief(
    path,
    source_hash,
    structural_summary,
    summary,
    role~,
    structural_terms~,
    summary_terms~,
  )
}

///|
fn build_or_update_orient_map(
  config : AgentOrientConfig,
  briefs : Array[LocalFileBrief],
  cached_map : AgentOrientMap?,
) -> AgentOrientMap {
  @map.build_or_update(config, briefs, cached_map)
}

///|
fn task_tokens(text : String) -> Array[String] {
  @matching.task_tokens(text)
}

///|
fn matched_terms_in_tokens(
  task_terms : Array[String],
  text_terms : Array[String],
) -> Array[String] {
  @matching.matched_terms_in_tokens(task_terms, text_terms)
}

///|
fn owner_task_terms_from_map(
  raw_terms : Array[String],
  orient_map : AgentOrientMap,
) -> Array[String] {
  @matching.owner_task_terms_from_map(raw_terms, orient_map)
}

///|
fn infer_file_role(
  file : SupportedFile,
  structural_terms : Array[String],
  summary_terms : Array[String],
  outgoing_count : Int,
  incoming_count : Int,
  external_terms? : Array[String] = [],
) -> String {
  @matching.infer_file_role(
    file,
    structural_terms,
    summary_terms,
    outgoing_count,
    incoming_count,
    external_terms~,
  )
}

///|
fn is_consumer_dominated_term(
  term : String,
  briefs : Array[LocalFileBrief],
) -> Bool {
  @matching.is_consumer_dominated_term(term, briefs)
}

///|
fn source_matches_owner(source : String, owner : String) -> Bool {
  @map.source_matches_owner(source, owner)
}

///|
fn wiki_page_is_owner_specific(page : LocalWikiPage) -> Bool {
  @map.wiki_page_is_owner_specific(page)
}

///|
fn likely_owners(
  orient_map : AgentOrientMap,
  task_terms : Array[String],
  task : String,
  limit : Int,
) -> Array[AgentOrientItem] {
  @owner.likely_owners(orient_map, task_terms, task, limit)
}

///|
fn likely_knowledge_sources(
  orient_map : AgentOrientMap,
  task_terms : Array[String],
  task : String,
  limit : Int,
) -> Array[AgentOrientItem] {
  @owner.likely_knowledge_sources(orient_map, task_terms, task, limit)
}

///|
fn score_briefs(
  briefs : Array[LocalFileBrief],
  task_terms : Array[String],
  task : String,
) -> Array[LocalFileBrief] {
  @matching.score_briefs(briefs, task_terms, task)
}

///|
fn required_preflight(
  orient_map : AgentOrientMap,
  owners : Array[AgentOrientItem],
  briefs : Array[LocalFileBrief],
  limit : Int,
) -> Array[AgentOrientItem] {
  @report.required_preflight(orient_map, owners, briefs, limit)
}

///|
fn readiness_quiz(
  likely_owners : Array[AgentOrientItem],
  knowledge_sources : Array[AgentOrientItem],
  consumer_surfaces : Array[AgentOrientItem],
  do_not_implement_here : Array[AgentOrientItem],
  required_preflight : Array[AgentOrientItem],
) -> Array[@types.AgentOrientQuizItem] {
  @report.readiness_quiz(
    likely_owners, knowledge_sources, consumer_surfaces, do_not_implement_here, required_preflight,
  )
}
