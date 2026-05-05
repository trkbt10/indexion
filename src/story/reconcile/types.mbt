/// Type definitions for spec-act ↔ impl-document reconciliation.
///
/// Reconcile operates on a finer-grained model than `analyze`: it walks
/// the spec side as a sequence of *acts* (numbered narrative beats parsed
/// from each spec document's headings) and matches each act to the impl
/// document that most closely mirrors it. From those matches it derives
/// candidate actions for the writer — expand a thin chapter, prune a
/// stray scene, restructure a multi-chapter act — backed by BM25 evidence.
///
/// "Act" and "match" are domain words for what is structurally just
/// "section of a spec doc" and "an impl doc". The story command surfaces
/// them under these names because that is the writer-facing vocabulary;
/// the underlying types do not care whether the project is a novel, a
/// design spec, or anything else.

///|
/// A single act extracted from a spec document. The act's body is the
/// content under its heading, ending at the next heading at the same
/// level (or the end of the document).
pub struct PlotAct {
  /// Source document path (as discovered).
  source_path : String
  /// Heading level (1 = top, 2 = ##, etc.).
  level : Int
  /// 1-based act number, derived from heading order within source_path.
  index : Int
  /// Heading text without leading "#" markers.
  title : String
  /// Body text under the heading.
  body : String
} derive(ToJson)

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
/// One side of a candidate alignment: the impl document that most closely
/// matches a given act, plus its similarity score.
pub struct ImplMatch {
  impl_path : String
  similarity : Double
} derive(ToJson)

///|
pub fn ImplMatch::get_impl_path(self : ImplMatch) -> String {
  self.impl_path
}

///|
pub fn ImplMatch::get_similarity(self : ImplMatch) -> Double {
  self.similarity
}

///|
/// Recommended action for a single act-to-impl mapping.
pub enum DriftAction {
  /// Mapping is healthy — no action needed.
  Ok
  /// Best impl similarity is below floor; act is under-represented.
  ExpandImpl
  /// Multiple impl docs score similarly; act may be split or diluted.
  ConsolidateImpl
  /// Best impl has high similarity but also heavy out-of-spec material.
  PruneStray
  /// No impl doc exceeds the similarity floor at all.
  MissingFromImpl
} derive(Eq, Show)

///|
pub fn DriftAction::label(self : DriftAction) -> String {
  match self {
    Ok => "ok"
    ExpandImpl => "expand-impl"
    ConsolidateImpl => "consolidate-impl"
    PruneStray => "prune-stray"
    MissingFromImpl => "missing-from-impl"
  }
}

///|
/// Custom ToJson: emit the kebab-case label so JSON consumers see the
/// same string as the text-format rationale prefix.
pub impl ToJson for DriftAction with to_json(self) {
  self.label().to_json()
}

///|
/// One reconcile candidate: an act, its best impl match, optional
/// runner-up matches, the recommended action, and supporting evidence.
pub struct ActReconcileCandidate {
  act : PlotAct
  best_match : ImplMatch?
  runner_ups : Array[ImplMatch]
  /// Terms in the act not picked up by the best-matching impl (under-coverage).
  missing_terms : Array[String]
  /// Terms in the best-matching impl not present in the act (out-of-source for this act).
  extra_terms : Array[String]
  /// Terms in the act that ARE present in the best-matching impl,
  /// ranked by the act-side BM25 weight. Symmetric complement of
  /// `missing_terms` from the same vocabulary computation.
  ///
  /// Interpretation depends on the polarity the caller assigned to
  /// the spec corpus:
  ///   - Standard polarity (spec is must-cover content): these terms
  ///     are positive — the act requirements the impl satisfied.
  ///   - Inverted polarity (spec is a constraint corpus the impl
  ///     must NOT echo, e.g. lint guidance fed as `--spec`): these
  ///     terms are the leak set — constraint vocabulary that
  ///     surfaced in impl when it should not have.
  /// Reconcile itself is polarity-agnostic; the project pipeline
  /// frames the interpretation.
  covered_terms : Array[String]
  action : DriftAction
  /// One-line human-readable rationale for the chosen action.
  rationale : String
} derive(ToJson)

///|
pub fn ActReconcileCandidate::get_act(
  self : ActReconcileCandidate,
) -> PlotAct {
  self.act
}

///|
pub fn ActReconcileCandidate::get_best_match(
  self : ActReconcileCandidate,
) -> ImplMatch? {
  self.best_match
}

///|
pub fn ActReconcileCandidate::get_runner_ups(
  self : ActReconcileCandidate,
) -> Array[ImplMatch] {
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
pub fn ActReconcileCandidate::get_covered_terms(
  self : ActReconcileCandidate,
) -> Array[String] {
  self.covered_terms
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
  acts : Array[PlotAct]
  impl_paths : Array[String]
  candidates : Array[ActReconcileCandidate]
  /// Impl docs that are not the best match for any act.
  orphan_impl : Array[String]
} derive(ToJson)

///|
pub fn ReconcileReport::get_acts(self : ReconcileReport) -> Array[PlotAct] {
  self.acts
}

///|
pub fn ReconcileReport::get_impl_paths(
  self : ReconcileReport,
) -> Array[String] {
  self.impl_paths
}

///|
pub fn ReconcileReport::get_candidates(
  self : ReconcileReport,
) -> Array[ActReconcileCandidate] {
  self.candidates
}

///|
pub fn ReconcileReport::get_orphan_impl(
  self : ReconcileReport,
) -> Array[String] {
  self.orphan_impl
}

///|
/// Configuration for the reconcile run.
pub struct ReconcileConfig {
  /// Minimum similarity for an impl doc to be considered a viable match.
  similarity_floor : Double
  /// Margin within which runner-ups are reported alongside the best match.
  runner_up_margin : Double
  /// Maximum unique missing/extra terms per candidate.
  max_terms_per_candidate : Int
  /// Optional KGF registry root override (mirrors StoryConfig).
  registry_root : String
}

///|
pub fn ReconcileConfig::new(
  similarity_floor~ : Double = 0.15,
  runner_up_margin~ : Double = 0.05,
  max_terms_per_candidate~ : Int = 8,
  registry_root~ : String = "",
) -> ReconcileConfig {
  {
    similarity_floor,
    runner_up_margin,
    max_terms_per_candidate,
    registry_root,
  }
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

///|
pub fn ReconcileConfig::get_registry_root(self : ReconcileConfig) -> String {
  self.registry_root
}
