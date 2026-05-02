/// Type definitions for story divergence analysis.
///
/// The story commands measure divergence between two document groups:
///
///   - **spec** group  — the source-of-truth side (plots, references,
///     research notes, scene memos, etc.)
///   - **impl** group  — the derived side (prose chapters, scenes,
///     drafts that expand the spec into final text)
///
/// What each side _means_ is not encoded in indexion. The user specifies
/// which files belong to which group via glob patterns on the command
/// line. Folder names and filenames carry no semantic weight: a writer
/// who keeps everything in `manuscript/spec.md` and `manuscript/text.md`
/// gets the same treatment as one who uses elaborate sub-folders.
///
/// This mirrors the spec ↔ implementation duality used by `plan reconcile`
/// elsewhere in indexion. The two commands are domain instances of the
/// same abstract relation: "a source-of-truth document group `A` is
/// expanded into a derived document group `B`; report where `B` drifts."

///|
/// One document loaded from disk. Carries only what the divergence engine
/// needs: a stable display path (used for attribution and ordering) and
/// the raw text content.
pub struct StoryDocument {
  /// Path as discovered, normalised to forward slashes. Used as the
  /// identifier in attribution outputs and as the path passed to KGF
  /// tokenization (so the spec sees the right extension).
  path : String
  /// Raw text content read from disk.
  content : String
}

///|
pub fn StoryDocument::new(path : String, content : String) -> StoryDocument {
  { path, content }
}

///|
pub fn StoryDocument::get_path(self : StoryDocument) -> String {
  self.path
}

///|
pub fn StoryDocument::get_content(self : StoryDocument) -> String {
  self.content
}

///|
/// The two document groups for one analysis or reconcile run. Always
/// non-empty checks are the caller's responsibility; an empty side
/// produces an empty report rather than an error so plan-style preview
/// commands can still surface useful information.
pub struct StoryGroups {
  spec : Array[StoryDocument]
  impl_ : Array[StoryDocument]
}

///|
pub fn StoryGroups::new(
  spec : Array[StoryDocument],
  impl_ : Array[StoryDocument],
) -> StoryGroups {
  { spec, impl_ }
}

///|
pub fn StoryGroups::get_spec(self : StoryGroups) -> Array[StoryDocument] {
  self.spec
}

///|
pub fn StoryGroups::get_impl(self : StoryGroups) -> Array[StoryDocument] {
  self.impl_
}

///|
/// Per-pair lexical similarity between one spec document and one impl
/// chapter (or whatever the impl side represents).
pub struct PairSimilarity {
  spec_path : String
  impl_path : String
  /// Cosine similarity in [0, 1].
  similarity : Double
} derive(ToJson)

///|
pub fn PairSimilarity::get_spec_path(self : PairSimilarity) -> String {
  self.spec_path
}

///|
pub fn PairSimilarity::get_impl_path(self : PairSimilarity) -> String {
  self.impl_path
}

///|
pub fn PairSimilarity::get_similarity(self : PairSimilarity) -> Double {
  self.similarity
}

///|
/// Terms present in the spec group but absent from the impl group —
/// under-coverage. Spec side is aggregated across all spec documents.
pub struct UnderCoverageTerm {
  value : String
  weight : Double
  /// Spec documents where this term originated, by path.
  origin_paths : Array[String]
} derive(ToJson)

///|
pub fn UnderCoverageTerm::get_value(self : UnderCoverageTerm) -> String {
  self.value
}

///|
pub fn UnderCoverageTerm::get_weight(self : UnderCoverageTerm) -> Double {
  self.weight
}

///|
pub fn UnderCoverageTerm::get_origin_paths(
  self : UnderCoverageTerm,
) -> Array[String] {
  self.origin_paths
}

///|
/// Terms present in the impl group but absent from any spec — out-of-source.
pub struct OutOfSourceTerm {
  value : String
  weight : Double
  /// Impl documents where this term appeared, by path.
  origin_paths : Array[String]
} derive(ToJson)

///|
pub fn OutOfSourceTerm::get_value(self : OutOfSourceTerm) -> String {
  self.value
}

///|
pub fn OutOfSourceTerm::get_weight(self : OutOfSourceTerm) -> Double {
  self.weight
}

///|
pub fn OutOfSourceTerm::get_origin_paths(
  self : OutOfSourceTerm,
) -> Array[String] {
  self.origin_paths
}

///|
/// Per-impl-document analysis: which spec documents contributed and how
/// much.
pub struct ChapterAttribution {
  impl_path : String
  /// Each entry: (spec_path, similarity).
  by_spec : Array[PairSimilarity]
  /// Aggregated cosine similarity to the union of all spec documents.
  combined_similarity : Double
} derive(ToJson)

///|
pub fn ChapterAttribution::get_impl_path(
  self : ChapterAttribution,
) -> String {
  self.impl_path
}

///|
pub fn ChapterAttribution::get_by_spec(
  self : ChapterAttribution,
) -> Array[PairSimilarity] {
  self.by_spec
}

///|
pub fn ChapterAttribution::get_combined_similarity(
  self : ChapterAttribution,
) -> Double {
  self.combined_similarity
}

///|
/// Top-level story divergence report.
pub struct StoryReport {
  spec_count : Int
  impl_count : Int
  /// Aggregate cosine distance between the union of spec and the union of
  /// impl. 0 = identical vocabulary, 1 = orthogonal.
  overall_distance : Double
  /// Per-impl attribution.
  attributions : Array[ChapterAttribution]
  /// Terms in spec but not in impl, ranked by weight desc.
  under_coverage : Array[UnderCoverageTerm]
  /// Terms in impl but not in spec, ranked by weight desc.
  out_of_source : Array[OutOfSourceTerm]
} derive(ToJson)

///|
pub fn StoryReport::get_spec_count(self : StoryReport) -> Int {
  self.spec_count
}

///|
pub fn StoryReport::get_impl_count(self : StoryReport) -> Int {
  self.impl_count
}

///|
pub fn StoryReport::get_overall_distance(self : StoryReport) -> Double {
  self.overall_distance
}

///|
pub fn StoryReport::get_attributions(
  self : StoryReport,
) -> Array[ChapterAttribution] {
  self.attributions
}

///|
pub fn StoryReport::get_under_coverage(
  self : StoryReport,
) -> Array[UnderCoverageTerm] {
  self.under_coverage
}

///|
pub fn StoryReport::get_out_of_source(
  self : StoryReport,
) -> Array[OutOfSourceTerm] {
  self.out_of_source
}

///|
/// Configuration for a story analyze run.
pub struct StoryConfig {
  /// Maximum terms to surface per divergence side.
  max_terms : Int
  /// Minimum value length for divergence terms.
  min_value_length : Int
  /// Optional registry resolution hint — story root used to discover the
  /// kgfs/story/ spec. Empty string means resolve from CWD only.
  registry_root : String
}

///|
pub fn StoryConfig::new(
  max_terms~ : Int = 20,
  min_value_length~ : Int = 2,
  registry_root~ : String = "",
) -> StoryConfig {
  { max_terms, min_value_length, registry_root }
}

///|
pub fn StoryConfig::get_max_terms(self : StoryConfig) -> Int {
  self.max_terms
}

///|
pub fn StoryConfig::get_min_value_length(self : StoryConfig) -> Int {
  self.min_value_length
}

///|
pub fn StoryConfig::get_registry_root(self : StoryConfig) -> String {
  self.registry_root
}
