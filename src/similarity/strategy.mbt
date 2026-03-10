///|
/// Unified similarity strategy interface.
/// Provides strategy kind enum and parsing.

///|
/// Strategy kind enum for unified handling.
pub enum StrategyKind {
  /// Normalized Compression Distance (semantic similarity).
  NCD
  /// TF-IDF cosine similarity (lexical similarity).
  TfIdf
  /// Weighted combination of NCD and TF-IDF.
  Hybrid(@types.HybridConfig)
  /// Tree edit distance (structural similarity).
  Apted
  /// Tree Structure Edit Distance.
  Tsed
}

///|
/// Parse strategy name to StrategyKind.
pub fn StrategyKind::parse(name : String) -> StrategyKind? {
  match name {
    "ncd" => Some(NCD)
    "tfidf" => Some(TfIdf)
    "hybrid" => Some(Hybrid(@types.HybridConfig::new()))
    "apted" => Some(Apted)
    "tsed" => Some(Tsed)
    _ => None
  }
}

///|
/// Parse strategy with optional hybrid weights.
pub fn StrategyKind::parse_with_weights(
  name : String,
  ncd_weight : Double,
  tfidf_weight : Double,
) -> StrategyKind? {
  match name {
    "ncd" => Some(NCD)
    "tfidf" => Some(TfIdf)
    "hybrid" =>
      Some(Hybrid(@types.HybridConfig::create(ncd_weight, tfidf_weight)))
    "apted" => Some(Apted)
    "tsed" => Some(Tsed)
    _ => None
  }
}

///|
/// Get strategy name.
pub fn StrategyKind::name(self : StrategyKind) -> String {
  match self {
    NCD => "ncd"
    TfIdf => "tfidf"
    Hybrid(_) => "hybrid"
    Apted => "apted"
    Tsed => "tsed"
  }
}

///|
/// Check if strategy operates on text (vs. trees).
pub fn StrategyKind::is_text_strategy(self : StrategyKind) -> Bool {
  match self {
    NCD | TfIdf | Hybrid(_) => true
    Apted | Tsed => false
  }
}

///|
/// Check if strategy operates on trees.
pub fn StrategyKind::is_tree_strategy(self : StrategyKind) -> Bool {
  not(self.is_text_strategy())
}

///|
/// List all available strategy names.
pub fn available_strategies() -> Array[String] {
  ["ncd", "tfidf", "hybrid", "apted", "tsed"]
}

///|
/// List text-only strategy names.
pub fn text_strategies() -> Array[String] {
  ["ncd", "tfidf", "hybrid"]
}

///|
/// List tree-only strategy names.
pub fn tree_strategies() -> Array[String] {
  ["apted", "tsed"]
}

///|
/// Calculate text similarity using the strategy.
/// Returns None for tree strategies.
pub fn StrategyKind::text_similarity(
  self : StrategyKind,
  text1 : String,
  text2 : String,
) -> @types.SimilarityResult? {
  match self {
    NCD => {
      let s = @ncd.NCDStrategy::new()
      Some(@types.SimilarityResult::from_similarity(s.similarity(text1, text2)))
    }
    TfIdf => {
      let s = @tfidf_strategy.TfidfStrategy::new()
      Some(@types.SimilarityResult::from_similarity(s.similarity(text1, text2)))
    }
    Hybrid(config) => {
      let s = @hybrid.HybridStrategy::with_config(config)
      Some(@types.SimilarityResult::from_similarity(s.similarity(text1, text2)))
    }
    Apted | Tsed => None
  }
}

///|
/// Calculate tree similarity using the strategy.
/// Returns None for text strategies.
pub fn StrategyKind::tree_similarity(
  self : StrategyKind,
  tree1 : @apted.TreeNode,
  tree2 : @apted.TreeNode,
) -> @types.SimilarityResult? {
  match self {
    Apted => {
      let config = @apted.CostConfig::default()
      let sim = @apted.tree_similarity(tree1, tree2, config)
      Some(@types.SimilarityResult::from_similarity(sim))
    }
    Tsed => {
      let config = @apted.TSEDConfig::default()
      let sim = @apted.calculate_tsed(tree1, tree2, config)
      Some(@types.SimilarityResult::from_similarity(sim))
    }
    NCD | TfIdf | Hybrid(_) => None
  }
}

///|
/// Calculate similarity with automatic dispatch based on input type.
/// For text strategies, compares strings directly.
/// For tree strategies, parses bracket notation into trees.
pub fn StrategyKind::calculate(
  self : StrategyKind,
  input1 : String,
  input2 : String,
) -> @types.SimilarityResult? {
  if self.is_text_strategy() {
    self.text_similarity(input1, input2)
  } else {
    // Parse bracket notation for tree strategies
    match (parse_bracket_tree(input1), parse_bracket_tree(input2)) {
      (Some(tree1), Some(tree2)) => self.tree_similarity(tree1, tree2)
      _ => None
    }
  }
}

///|
/// Parse bracket notation into TreeNode.
/// Format: "Label" or "Label(Child1,Child2,...)"
pub fn parse_bracket_tree(s : String) -> @apted.TreeNode? {
  let chars = s.to_array()
  if chars.length() == 0 {
    return None
  }
  let (tree, _) = parse_tree_recursive(chars, 0)
  Some(tree)
}

///|
/// Recursive tree parser for bracket notation.
fn parse_tree_recursive(
  chars : Array[Char],
  start : Int,
) -> (@apted.TreeNode, Int) {
  let label_chars : Array[Char] = []
  let mut i = start
  while i < chars.length() {
    let c = chars[i]
    if c == '(' || c == ',' || c == ')' {
      break
    }
    label_chars.push(c)
    i += 1
  }
  let label = String::from_array(label_chars)
  if i < chars.length() && chars[i] == '(' {
    let children : Array[@apted.TreeNode] = []
    i += 1
    while i < chars.length() && chars[i] != ')' {
      if chars[i] == ',' {
        i += 1
        continue
      }
      let (child, new_i) = parse_tree_recursive(chars, i)
      children.push(child)
      i = new_i
    }
    if i < chars.length() && chars[i] == ')' {
      i += 1
    }
    (@apted.TreeNode::node(label, children), i)
  } else {
    (@apted.TreeNode::leaf(label), i)
  }
}
