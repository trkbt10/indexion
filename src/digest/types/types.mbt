// Type definitions for digest module (reminiscent backtracking).
// Enables purpose-based function lookup using vector embeddings.

///|
/// Hash of function content (SHA-256 truncated to 32 hex characters).
/// Used for change detection at function level.
pub struct FunctionHash {
  value : String
} derive(Eq, Debug, ToJson, @json.FromJson, Hash)

///|
/// Create a FunctionHash from a string value.
pub fn FunctionHash::from_string(s : String) -> FunctionHash {
  { value: s }
}

///|
/// Get the hash value as a string.
pub fn FunctionHash::to_string(self : FunctionHash) -> String {
  self.value
}

///|
/// Impression represents LLM-generated or extracted purpose description.
/// This is the semantic representation of "what does this function do".
pub struct Impression {
  /// One-line purpose description (e.g., "ファイルを読み込んでJSONにパースする").
  summary : String
  /// Extracted keywords for TF-IDF based matching.
  keywords : Array[String]
  /// Optional expanded context for richer understanding.
  context : String?
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Create a new Impression.
pub fn Impression::new(
  summary : String,
  keywords : Array[String],
  context? : String? = None,
) -> Impression {
  { summary, keywords, context }
}

///|
/// Create an Impression from just a summary (auto-extract keywords later).
pub fn Impression::from_summary(summary : String) -> Impression {
  { summary, keywords: [], context: None }
}

///|
/// Get the full text representation for embedding.
pub fn Impression::to_text(self : Impression) -> String {
  let mut text = self.summary
  if self.keywords.length() > 0 {
    text = text + " " + self.keywords.join(" ")
  }
  match self.context {
    Some(ctx) => text = text + " " + ctx
    None => ()
  }
  text
}

///|
/// FunctionUnit encapsulates a function with its context.
/// This is the unit of indexing for reminiscent backtracking.
pub struct FunctionUnit {
  /// Reference to the function symbol from CodeGraph.
  symbol : @graph.SymbolNode
  /// Module ID this function belongs to.
  module_id : String
  /// Hash of function body (for change detection).
  source_hash : FunctionHash
  /// Hash including call relationships (for context change detection).
  context_hash : FunctionHash
  /// Symbol IDs of functions that call this function.
  callers : Array[String]
  /// Symbol IDs of functions this function calls.
  callees : Array[String]
  /// LLM-generated or extracted purpose (nullable for incremental build).
  impression : Impression?
  /// Depth in call graph (0 = leaf function with no callees).
  depth : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Create a new FunctionUnit.
pub fn FunctionUnit::new(
  symbol : @graph.SymbolNode,
  module_id : String,
  source_hash : FunctionHash,
  context_hash : FunctionHash,
  callers : Array[String],
  callees : Array[String],
  depth : Int,
) -> FunctionUnit {
  {
    symbol,
    module_id,
    source_hash,
    context_hash,
    callers,
    callees,
    impression: None,
    depth,
  }
}

///|
/// Create a FunctionUnit with an impression.
pub fn FunctionUnit::with_impression(
  self : FunctionUnit,
  impression : Impression,
) -> FunctionUnit {
  { ..self, impression: Some(impression) }
}

///|
/// Check if this is a leaf function (no outgoing calls).
pub fn FunctionUnit::is_leaf(self : FunctionUnit) -> Bool {
  self.callees.length() == 0
}

///|
/// Get the function ID (same as symbol ID).
pub fn FunctionUnit::id(self : FunctionUnit) -> String {
  self.symbol.id
}

///|
/// Get the function name.
pub fn FunctionUnit::name(self : FunctionUnit) -> String {
  self.symbol.name
}

///|
/// Embedding vector result for a function.
pub struct FunctionEmbedding {
  /// Function ID (symbol ID).
  function_id : String
  /// Dense embedding vector.
  vector : Array[Double]
  /// Source of embedding ("tfidf", "remote", etc.).
  source : String
} derive(Eq, Debug)

///|
/// Create a new FunctionEmbedding.
pub fn FunctionEmbedding::new(
  function_id : String,
  vector : Array[Double],
  source : String,
) -> FunctionEmbedding {
  { function_id, vector, source }
}

///|
/// Query hit result from purpose-based search.
pub struct QueryHit {
  /// The matched function unit.
  function : FunctionUnit
  /// Similarity score (higher = more similar).
  score : Double
  /// Keywords that contributed to the match.
  matched_keywords : Array[String]
} derive(Eq, Debug)

///|
/// Create a new QueryHit.
pub fn QueryHit::new(
  function : FunctionUnit,
  score : Double,
  matched_keywords : Array[String],
) -> QueryHit {
  { function, score, matched_keywords }
}

///|
/// Query options for purpose-based search.
pub struct QueryOptions {
  /// Number of results to return.
  top_k : Int
  /// Minimum similarity score threshold.
  min_score : Double
  /// Filter by module pattern (optional).
  filter_module : String?
  /// Filter by symbol kind (optional).
  filter_kind : String?
} derive(Eq, Debug)

///|
/// Create default QueryOptions.
pub fn QueryOptions::default() -> QueryOptions {
  { top_k: 10, min_score: 0.1, filter_module: None, filter_kind: None }
}

///|
/// Create QueryOptions with top_k.
pub fn QueryOptions::with_top_k(k : Int) -> QueryOptions {
  { ..QueryOptions::default(), top_k: k }
}
