/// Type definitions for plot ↔ prose reconciliation.
///
/// Reconcile operates on a finer-grained model than `analyze`: it walks the
/// plot side as a sequence of *acts* (numbered narrative beats parsed from a
/// plot document's headings) and matches each act to the prose chapter that
/// most closely mirrors it. From those matches it derives candidate actions
/// for the writer — expand a thin chapter, prune a stray scene, restructure
/// a multi-chapter act — backed by BM25 evidence.

///|
/// A single act extracted from a plot document. The act's body is the prose
/// content under its heading, ending at the next heading at the same level
/// or below.
pub struct PlotAct {
  /// Source document path (relative).
  source_path : String
  /// Heading level (1 = top, 2 = ##, etc.).
  level : Int
  /// 1-based act number, derived from heading order within source_path.
  index : Int
  /// Heading text without leading "#" markers.
  title : String
  /// Body text under the heading.
  body : String
}

///|
pub fn PlotAct::get_source_path(self : PlotAct) -> String {
  self.source_path
}

///|
pub fn PlotAct::get_index(self : PlotAct) -> Int {
  self.index
}

///|
pub fn PlotAct::get_title(self : PlotAct) -> String {
  self.title
}

///|
pub fn PlotAct::get_body(self : PlotAct) -> String {
  self.body
}

///|
pub fn PlotAct::get_level(self : PlotAct) -> Int {
  self.level
}

///|
/// One side of a candidate alignment: the prose chapter that most closely
/// matches a given act, plus any runner-up matches that exceed a similarity
/// floor.
pub struct ChapterMatch {
  prose_path : String
  similarity : Double
}

///|
pub fn ChapterMatch::get_prose_path(self : ChapterMatch) -> String {
  self.prose_path
}

///|
pub fn ChapterMatch::get_similarity(self : ChapterMatch) -> Double {
  self.similarity
}

///|
/// Recommended action for a single act-to-chapter mapping.
pub enum DriftAction {
  /// Mapping is healthy — no action needed.
  Ok
  /// Best chapter similarity is below floor; act is under-represented in prose.
  ExpandProse
  /// Multiple chapters score similarly; act may be split or diluted.
  ConsolidateChapters
  /// Best chapter has high similarity but also heavy out-of-source noise.
  PruneStrayScenes
  /// No chapter exceeds the similarity floor at all.
  MissingFromProse
} derive(Eq, Show)

///|
pub fn DriftAction::label(self : DriftAction) -> String {
  match self {
    Ok => "ok"
    ExpandProse => "expand-prose"
    ConsolidateChapters => "consolidate-chapters"
    PruneStrayScenes => "prune-stray-scenes"
    MissingFromProse => "missing-from-prose"
  }
}

///|
/// One reconcile candidate: an act, its best chapter match, optional
/// runner-up matches, the recommended action, and supporting evidence.
pub struct ActReconcileCandidate {
  act : PlotAct
  best_match : ChapterMatch?
  runner_ups : Array[ChapterMatch]
  /// Terms in the act not picked up by the best-matching chapter (under-coverage).
  missing_terms : Array[String]
  /// Terms in the best-matching chapter not present in the act (out-of-source for this act).
  extra_terms : Array[String]
  action : DriftAction
  /// One-line human-readable rationale for the chosen action.
  rationale : String
}

///|
pub fn ActReconcileCandidate::get_act(
  self : ActReconcileCandidate,
) -> PlotAct {
  self.act
}

///|
pub fn ActReconcileCandidate::get_best_match(
  self : ActReconcileCandidate,
) -> ChapterMatch? {
  self.best_match
}

///|
pub fn ActReconcileCandidate::get_runner_ups(
  self : ActReconcileCandidate,
) -> Array[ChapterMatch] {
  self.runner_ups
}

///|
pub fn ActReconcileCandidate::get_missing_terms(
  self : ActReconcileCandidate,
) -> Array[String] {
  self.missing_terms
}

///|
pub fn ActReconcileCandidate::get_extra_terms(
  self : ActReconcileCandidate,
) -> Array[String] {
  self.extra_terms
}

///|
pub fn ActReconcileCandidate::get_action(
  self : ActReconcileCandidate,
) -> DriftAction {
  self.action
}

///|
pub fn ActReconcileCandidate::get_rationale(
  self : ActReconcileCandidate,
) -> String {
  self.rationale
}

///|
/// Top-level reconcile report.
pub struct ReconcileReport {
  root : String
  acts : Array[PlotAct]
  prose_paths : Array[String]
  candidates : Array[ActReconcileCandidate]
  /// Chapters that are not the best match for any act — orphan chapters.
  orphan_chapters : Array[String]
}

///|
pub fn ReconcileReport::get_root(self : ReconcileReport) -> String {
  self.root
}

///|
pub fn ReconcileReport::get_acts(self : ReconcileReport) -> Array[PlotAct] {
  self.acts
}

///|
pub fn ReconcileReport::get_prose_paths(
  self : ReconcileReport,
) -> Array[String] {
  self.prose_paths
}

///|
pub fn ReconcileReport::get_candidates(
  self : ReconcileReport,
) -> Array[ActReconcileCandidate] {
  self.candidates
}

///|
pub fn ReconcileReport::get_orphan_chapters(
  self : ReconcileReport,
) -> Array[String] {
  self.orphan_chapters
}

///|
/// Configuration for the reconcile run.
pub struct ReconcileConfig {
  /// Story root directory (absolute or as supplied by the user).
  root : String
  /// Minimum similarity for a chapter to be considered a viable match.
  similarity_floor : Double
  /// Margin within which runner-ups are reported alongside the best match.
  runner_up_margin : Double
  /// Maximum unique missing/extra terms per candidate.
  max_terms_per_candidate : Int
}

///|
pub fn ReconcileConfig::new(
  root : String,
  similarity_floor~ : Double = 0.15,
  runner_up_margin~ : Double = 0.05,
  max_terms_per_candidate~ : Int = 8,
) -> ReconcileConfig {
  { root, similarity_floor, runner_up_margin, max_terms_per_candidate }
}

///|
pub fn ReconcileConfig::get_root(self : ReconcileConfig) -> String {
  self.root
}

///|
pub fn ReconcileConfig::get_similarity_floor(self : ReconcileConfig) -> Double {
  self.similarity_floor
}

///|
pub fn ReconcileConfig::get_runner_up_margin(self : ReconcileConfig) -> Double {
  self.runner_up_margin
}

///|
pub fn ReconcileConfig::get_max_terms_per_candidate(
  self : ReconcileConfig,
) -> Int {
  self.max_terms_per_candidate
}
