/// Type definitions for n:m story divergence analysis.
///
/// Story analysis treats a novel-writing project as an n:m mapping:
///   sources/ (plot, references, scene-notes)  →  prose/ (chapters)
///
/// Multiple supply-side documents (plot drafts, character sheets, settings,
/// research notes) feed into multiple derived documents (chapters, scenes).
/// The divergence analyzer measures vocabulary flow in both directions to
/// detect under-coverage (sources not reflected in prose) and out-of-source
/// material (prose not traceable to any source).

///|
/// Classification of a source document by its sub-folder location.
pub enum SourceKind {
  Plot
  Reference
  SceneNote
  OtherSource
} derive(Eq, Show)

///|
pub fn SourceKind::label(self : SourceKind) -> String {
  match self {
    Plot => "plot"
    Reference => "reference"
    SceneNote => "scene-note"
    OtherSource => "source"
  }
}

///|
/// A supply-side document: plot draft, character sheet, setting reference,
/// or scene note. Identified by relative path under `sources/`.
pub struct SourceDoc {
  /// Path relative to the story root (e.g. "sources/plot/01-outline.md").
  rel_path : String
  /// Document name without extension, used for display.
  display_name : String
  /// Sub-folder classification.
  kind : SourceKind
  /// Raw text content.
  content : String
} derive(Show)

///|
pub fn SourceDoc::new(
  rel_path : String,
  display_name : String,
  kind : SourceKind,
  content : String,
) -> SourceDoc {
  { rel_path, display_name, kind, content }
}

///|
pub fn SourceDoc::get_rel_path(self : SourceDoc) -> String {
  self.rel_path
}

///|
pub fn SourceDoc::get_display_name(self : SourceDoc) -> String {
  self.display_name
}

///|
pub fn SourceDoc::get_kind(self : SourceDoc) -> SourceKind {
  self.kind
}

///|
pub fn SourceDoc::get_content(self : SourceDoc) -> String {
  self.content
}

///|
/// A derived prose document: a chapter or scene.
pub struct ProseDoc {
  /// Path relative to the story root (e.g. "prose/01-chapter.txt").
  rel_path : String
  /// Document name without extension.
  display_name : String
  /// Raw text content.
  content : String
} derive(Show)

///|
pub fn ProseDoc::new(
  rel_path : String,
  display_name : String,
  content : String,
) -> ProseDoc {
  { rel_path, display_name, content }
}

///|
pub fn ProseDoc::get_rel_path(self : ProseDoc) -> String {
  self.rel_path
}

///|
pub fn ProseDoc::get_display_name(self : ProseDoc) -> String {
  self.display_name
}

///|
pub fn ProseDoc::get_content(self : ProseDoc) -> String {
  self.content
}

///|
/// All documents loaded from a single story directory.
pub struct StoryDataset {
  /// Story root directory (absolute or as supplied by the user).
  root : String
  /// Supply-side documents.
  sources : Array[SourceDoc]
  /// Derived prose documents.
  prose : Array[ProseDoc]
}

///|
pub fn StoryDataset::new(
  root : String,
  sources : Array[SourceDoc],
  prose : Array[ProseDoc],
) -> StoryDataset {
  { root, sources, prose }
}

///|
pub fn StoryDataset::get_root(self : StoryDataset) -> String {
  self.root
}

///|
pub fn StoryDataset::get_sources(self : StoryDataset) -> Array[SourceDoc] {
  self.sources
}

///|
pub fn StoryDataset::get_prose(self : StoryDataset) -> Array[ProseDoc] {
  self.prose
}

///|
/// Per-pair lexical similarity between one source and one prose chapter.
pub struct PairSimilarity {
  source_path : String
  prose_path : String
  /// Cosine similarity in [0, 1].
  similarity : Double
}

///|
pub fn PairSimilarity::get_source_path(self : PairSimilarity) -> String {
  self.source_path
}

///|
pub fn PairSimilarity::get_prose_path(self : PairSimilarity) -> String {
  self.prose_path
}

///|
pub fn PairSimilarity::get_similarity(self : PairSimilarity) -> Double {
  self.similarity
}

///|
/// Terms present in sources but absent from prose — under-coverage.
/// Sources side is aggregated across all source docs.
pub struct UnderCoverageTerm {
  value : String
  weight : Double
  /// Source documents where this term originated, by relative path.
  origin_paths : Array[String]
}

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
/// Terms present in prose but absent from any source — out-of-source drift.
pub struct OutOfSourceTerm {
  value : String
  weight : Double
  /// Prose documents where this term appeared, by relative path.
  origin_paths : Array[String]
}

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
/// Per-prose chapter analysis: which sources contributed and how much.
pub struct ChapterAttribution {
  prose_path : String
  /// Each entry: (source_rel_path, similarity).
  by_source : Array[PairSimilarity]
  /// Aggregated cosine similarity to the union of all sources.
  combined_similarity : Double
}

///|
pub fn ChapterAttribution::get_prose_path(self : ChapterAttribution) -> String {
  self.prose_path
}

///|
pub fn ChapterAttribution::get_by_source(
  self : ChapterAttribution,
) -> Array[PairSimilarity] {
  self.by_source
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
  root : String
  source_count : Int
  prose_count : Int
  /// Aggregate cosine distance between the union of sources and the union of prose.
  overall_distance : Double
  /// Per-chapter attribution (which sources contributed, similarity per source).
  attributions : Array[ChapterAttribution]
  /// Terms in sources but not in prose, ranked by weight desc.
  under_coverage : Array[UnderCoverageTerm]
  /// Terms in prose but not in sources, ranked by weight desc.
  out_of_source : Array[OutOfSourceTerm]
}

///|
pub fn StoryReport::get_root(self : StoryReport) -> String {
  self.root
}

///|
pub fn StoryReport::get_source_count(self : StoryReport) -> Int {
  self.source_count
}

///|
pub fn StoryReport::get_prose_count(self : StoryReport) -> Int {
  self.prose_count
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
/// Configuration for story analysis.
pub struct StoryConfig {
  /// Story root directory.
  root : String
  /// Maximum terms to surface per divergence side.
  max_terms : Int
  /// Minimum value length for divergence terms.
  min_value_length : Int
}

///|
pub fn StoryConfig::new(
  root : String,
  max_terms~ : Int = 20,
  min_value_length~ : Int = 2,
) -> StoryConfig {
  { root, max_terms, min_value_length }
}

///|
pub fn StoryConfig::get_root(self : StoryConfig) -> String {
  self.root
}

///|
pub fn StoryConfig::get_max_terms(self : StoryConfig) -> Int {
  self.max_terms
}

///|
pub fn StoryConfig::get_min_value_length(self : StoryConfig) -> Int {
  self.min_value_length
}
