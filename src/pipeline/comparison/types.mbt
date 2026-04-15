///|
/// Batch comparison SoT (Single Source of Truth).
/// All CLI commands (explore, refactor, solid) should use this module
/// for batch similarity computation.

///|
/// A file entry with display name and content for batch comparison.
pub struct FileEntry {
  /// Display name (e.g., "pkg1:auth/client.ts" or just "auth/client.ts")
  display_name : String
  /// File content
  content : String
} derive(Eq, Debug)

///|
/// Create a FileEntry.
pub fn FileEntry::new(display_name : String, content : String) -> FileEntry {
  { display_name, content }
}

///|
/// A similarity match between two files.
pub struct SimilarityMatch {
  /// Index of first file
  index1 : Int
  /// Index of second file
  index2 : Int
  /// Display name of first file
  file1 : String
  /// Display name of second file
  file2 : String
  /// Similarity score in [0, 1] where 1 = identical
  similarity : Double
} derive(Eq, Debug)

///|
/// Create a SimilarityMatch.
pub fn SimilarityMatch::new(
  index1 : Int,
  index2 : Int,
  file1 : String,
  file2 : String,
  similarity : Double,
) -> SimilarityMatch {
  { index1, index2, file1, file2, similarity }
}

///|
/// Batch comparison configuration.
pub struct BatchConfig {
  /// Minimum similarity threshold in [0, 1]
  threshold : Double
  /// Strategy to use: "hybrid", "tfidf", "apted", or "tsed"
  strategy : String
} derive(Eq, Debug)

///|
/// Create a BatchConfig with defaults (hybrid, 0.8 threshold).
pub fn BatchConfig::new() -> BatchConfig {
  { threshold: 0.8, strategy: "hybrid" }
}

///|
/// Create a BatchConfig with custom values.
pub fn BatchConfig::create(
  threshold : Double,
  strategy : String,
) -> BatchConfig {
  { threshold, strategy }
}

///|
/// Batch comparison result with statistics.
pub struct BatchResult {
  /// Matching pairs above threshold
  matches : Array[SimilarityMatch]
  /// Number of files processed
  file_count : Int
  /// Total pairs compared (before filtering)
  pairs_compared : Int
} derive(Eq, Debug)

///|
/// Get matches from result.
pub fn BatchResult::get_matches(self : BatchResult) -> Array[SimilarityMatch] {
  self.matches
}

///|
/// File count below which brute-force pair enumeration is used
/// instead of TF-IDF pre-filtering.
let prefilter_min_files : Int = 10

///|
/// File count above which MinHash+LSH is used instead of TF-IDF
/// inverted index for candidate generation. LSH scales near-linearly
/// while TF-IDF inverted index degrades on large vocabulary sets.
let minhash_min_files : Int = 200

///|
/// TF-IDF threshold relaxation factor for pre-filtering.
/// Lower means more candidates pass the pre-filter.
let prefilter_factor : Double = 0.5

///|
/// Run batch comparison with the specified strategy.
pub fn compare(files : Array[FileEntry], config : BatchConfig) -> BatchResult {
  match config.strategy {
    "apted" => compare_apted(files, config.threshold)
    "tsed" => compare_tsed(files, config.threshold)
    "tfidf" => compare_tfidf(files, config.threshold)
    "bm25" => compare_bm25(files, config.threshold)
    "jsd" => compare_jsd(files, config.threshold)
    _ => compare_hybrid(files, config.threshold)
  }
}

///|
/// Filter matches to only cross-directory pairs.
pub fn filter_cross_directory(
  matches : Array[SimilarityMatch],
) -> Array[SimilarityMatch] {
  let filtered : Array[SimilarityMatch] = []
  for m in matches {
    let prefix1 = get_dirname_prefix(m.file1)
    let prefix2 = get_dirname_prefix(m.file2)
    if prefix1 != prefix2 {
      filtered.push(m)
    }
  }
  filtered
}

///|
fn get_dirname_prefix(display_name : String) -> String {
  let chars = display_name.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == ':' {
      let result : Array[Char] = []
      for j = 0; j < i; j = j + 1 {
        result.push(chars[j])
      }
      return String::from_array(result)
    }
  }
  ""
}
