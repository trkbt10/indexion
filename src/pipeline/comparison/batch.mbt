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
} derive(Eq, Show)

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
} derive(Eq, Show)

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
  /// Strategy to use: "tfidf", "apted", or "tsed"
  strategy : String
} derive(Eq, Show)

///|
/// Create a BatchConfig with defaults (tfidf, 0.8 threshold).
pub fn BatchConfig::new() -> BatchConfig {
  { threshold: 0.8, strategy: "tfidf" }
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
} derive(Eq, Show)

///|
/// Get matches from result.
pub fn BatchResult::get_matches(self : BatchResult) -> Array[SimilarityMatch] {
  self.matches
}

///|
/// Run batch comparison using TF-IDF strategy.
/// This is the primary batch comparison method for text similarity.
pub fn compare_tfidf(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  if files.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0 }
  }
  // Prepare files as (path, content) pairs for KGF tokenization
  let file_pairs : Array[(String, String)] = []
  for file in files {
    file_pairs.push((file.display_name, file.content))
  }
  // Tokenize with KGF
  let registry = @kgf_features.load_registry()
  let (tokenized, _) = @kgf_features.tokenize_files_with_kgf(
    file_pairs, registry,
  )
  // Build TF-IDF batch and find pairs
  let batch = @tfidf.TfidfBatch::from_tokens(tokenized)
  let pairs = batch.all_pairs_above_threshold(threshold)
  // Convert to SimilarityMatch
  let matches : Array[SimilarityMatch] = []
  for pair in pairs {
    let (i, j, sim) = pair
    matches.push(
      SimilarityMatch::new(
        i,
        j,
        files[i].display_name,
        files[j].display_name,
        sim,
      ),
    )
  }
  // Calculate total pairs
  let n = files.length()
  let total_pairs = n * (n - 1) / 2
  { matches, file_count: n, pairs_compared: total_pairs }
}

///|
/// Run batch comparison using APTED strategy.
/// Compares function-level AST structures.
pub fn compare_apted(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  if files.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0 }
  }
  // Extract function trees from each file
  let registry = @kgf_features.load_registry()
  let all_trees : Array[Array[@apted.TreeNode]] = []
  for file in files {
    let trees = extract_file_trees(file, registry)
    all_trees.push(trees)
  }
  // Compare trees across files
  let matches : Array[SimilarityMatch] = []
  let mut pairs_compared = 0
  let n = files.length()
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      let trees_i = all_trees[i]
      let trees_j = all_trees[j]
      // Find best matching pair of trees
      let mut best_sim = 0.0
      for ti in trees_i {
        for tj in trees_j {
          pairs_compared += 1
          let sim = @apted.tree_similarity(ti, tj, @apted.CostConfig::default())
          if sim > best_sim {
            best_sim = sim
          }
        }
      }
      if best_sim >= threshold {
        matches.push(
          SimilarityMatch::new(
            i,
            j,
            files[i].display_name,
            files[j].display_name,
            best_sim,
          ),
        )
      }
    }
  }
  { matches, file_count: n, pairs_compared }
}

///|
/// Run batch comparison using TSED strategy.
/// Compares tree structure edit distance.
pub fn compare_tsed(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  if files.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0 }
  }
  let registry = @kgf_features.load_registry()
  let all_trees : Array[Array[@apted.TreeNode]] = []
  for file in files {
    let trees = extract_file_trees(file, registry)
    all_trees.push(trees)
  }
  let matches : Array[SimilarityMatch] = []
  let mut pairs_compared = 0
  let n = files.length()
  let config = @apted.TSEDConfig::default()
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      let trees_i = all_trees[i]
      let trees_j = all_trees[j]
      let mut best_sim = 0.0
      for ti in trees_i {
        for tj in trees_j {
          pairs_compared += 1
          let sim = @apted.calculate_tsed(ti, tj, config)
          if sim > best_sim {
            best_sim = sim
          }
        }
      }
      if best_sim >= threshold {
        matches.push(
          SimilarityMatch::new(
            i,
            j,
            files[i].display_name,
            files[j].display_name,
            best_sim,
          ),
        )
      }
    }
  }
  { matches, file_count: n, pairs_compared }
}

///|
/// Run batch comparison with the specified strategy.
pub fn compare(files : Array[FileEntry], config : BatchConfig) -> BatchResult {
  match config.strategy {
    "apted" => compare_apted(files, config.threshold)
    "tsed" => compare_tsed(files, config.threshold)
    _ => compare_tfidf(files, config.threshold)
  }
}

///|
/// Extract tree representations from a file.
fn extract_file_trees(
  file : FileEntry,
  registry : @kgf_registry.KGFRegistry?,
) -> Array[@apted.TreeNode] {
  let trees : Array[@apted.TreeNode] = []
  // Use KGF function extraction if available
  guard registry.is_empty() == false else {
    // Fallback: create a single tree from content
    let tokens = simple_tokenize(file.content)
    trees.push(tokens_to_simple_tree(tokens))
    return trees
  }
  let reg = registry.unwrap()
  // Detect language from path
  guard reg.detect_from_path(file.display_name).is_empty() == false else {
    let tokens = simple_tokenize(file.content)
    trees.push(tokens_to_simple_tree(tokens))
    return trees
  }
  let lang = reg.detect_from_path(file.display_name).unwrap()
  guard reg.get_spec(lang).is_empty() == false else {
    let tokens = simple_tokenize(file.content)
    trees.push(tokens_to_simple_tree(tokens))
    return trees
  }
  let spec = reg.get_spec(lang).unwrap()
  // Tokenize with KGF lexer
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let kgf_tokens = lexer.tokenize(file.content)
  // Try to extract functions
  let funcs = @kgf_features.extract_function_trees(
    kgf_tokens,
    file.display_name,
  )
  if funcs.is_empty() {
    // No functions found, use whole file as tree
    let tokens = simple_tokenize(file.content)
    trees.push(tokens_to_simple_tree(tokens))
  } else {
    for func in funcs {
      trees.push(func.1)
    }
  }
  trees
}

///|
/// Simple tokenization for files without KGF support.
fn simple_tokenize(content : String) -> Array[String] {
  let tokens : Array[String] = []
  let current : Array[Char] = []
  for c in content {
    if c == ' ' || c == '\n' || c == '\t' || c == '\r' {
      if current.length() > 0 {
        tokens.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(c)
    }
  }
  if current.length() > 0 {
    tokens.push(String::from_array(current))
  }
  tokens
}

///|
/// Convert tokens to a simple tree.
fn tokens_to_simple_tree(tokens : Array[String]) -> @apted.TreeNode {
  if tokens.is_empty() {
    return @apted.TreeNode::leaf("empty")
  }
  let children : Array[@apted.TreeNode] = []
  for i, token in tokens {
    if i < 100 {
      // Limit tree size
      children.push(@apted.TreeNode::leaf(truncate_str(token, 20)))
    }
  }
  @apted.TreeNode::node("root", children)
}

///|
/// Truncate string for tree labels.
fn truncate_str(s : String, max : Int) -> String {
  let chars = s.to_array()
  if chars.length() <= max {
    return s
  }
  let result : Array[Char] = []
  for i = 0; i < max - 3; i = i + 1 {
    result.push(chars[i])
  }
  result.push('.')
  result.push('.')
  result.push('.')
  String::from_array(result)
}

///|
/// Filter matches to only cross-directory pairs.
/// A cross-directory pair has different dirname prefixes.
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
/// Extract dirname prefix from display name (before ':').
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
  "" // No prefix
}
