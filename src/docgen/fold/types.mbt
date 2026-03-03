// Types for graph folding and importance scoring.

///|
/// Importance score for a node in the dependency graph.
/// Combines multiple signals into a normalized [0, 1] score.
pub struct NodeImportance {
  /// Node identifier (module or symbol ID).
  id : String
  /// Composite importance score in [0, 1]. Higher = more important.
  score : Double
  /// Individual signal scores for transparency.
  signals : ImportanceSignals
}

///|
/// Individual importance signals before aggregation.
pub struct ImportanceSignals {
  /// Normalized reference count (how often this node is referenced).
  ref_score : Double
  /// Normalized edge centrality (fan-in + fan-out).
  centrality_score : Double
  /// TF-IDF uniqueness score (how distinct this node's name is).
  tfidf_score : Double
}

///|
pub fn NodeImportance::new(
  id : String,
  score : Double,
  signals : ImportanceSignals,
) -> NodeImportance {
  { id, score, signals }
}

///|
pub fn ImportanceSignals::new(
  ref_score : Double,
  centrality_score : Double,
  tfidf_score : Double,
) -> ImportanceSignals {
  { ref_score, centrality_score, tfidf_score }
}

///|
pub fn ImportanceSignals::zero() -> ImportanceSignals {
  { ref_score: 0.0, centrality_score: 0.0, tfidf_score: 0.0 }
}

///|
/// A folded node: either a real node or a cluster of collapsed nodes.
pub(all) enum FoldedNode {
  /// A preserved individual node with its importance.
  Single(String, Double)
  /// A cluster of collapsed nodes, with a label, member count, and member IDs.
  Cluster(String, Int, Array[String])
}

///|
/// A folded edge between two folded node IDs.
pub struct FoldedEdge {
  from : String
  to : String
  weight : Int
}

///|
pub fn FoldedEdge::new(
  from : String,
  to : String,
  weight : Int,
) -> FoldedEdge {
  { from, to, weight }
}

///|
/// Result of graph folding: a simplified graph structure.
pub struct FoldedGraph {
  nodes : Map[String, FoldedNode]
  edges : Array[FoldedEdge]
  depth : Int
}

///|
pub fn FoldedGraph::new(
  nodes : Map[String, FoldedNode],
  edges : Array[FoldedEdge],
  depth : Int,
) -> FoldedGraph {
  { nodes, edges, depth }
}

///|
pub fn FoldedGraph::get_nodes(self : FoldedGraph) -> Map[String, FoldedNode] {
  self.nodes
}

///|
pub fn FoldedGraph::get_edges(self : FoldedGraph) -> Array[FoldedEdge] {
  self.edges
}

///|
pub fn FoldedGraph::get_depth(self : FoldedGraph) -> Int {
  self.depth
}

///|
pub fn FoldedGraph::node_count(self : FoldedGraph) -> Int {
  self.nodes.length()
}

///|
/// Configuration for graph folding.
pub struct FoldConfig {
  /// Maximum number of visible nodes after folding.
  max_nodes : Int
  /// Importance threshold below which nodes get folded. [0, 1]
  threshold : Double
  /// Maximum recursion depth for folding passes.
  max_depth : Int
  /// Weights for importance signal aggregation.
  ref_weight : Double
  centrality_weight : Double
  tfidf_weight : Double
}

///|
pub fn FoldConfig::default() -> FoldConfig {
  {
    max_nodes: 15,
    threshold: 0.3,
    max_depth: 5,
    ref_weight: 0.4,
    centrality_weight: 0.35,
    tfidf_weight: 0.25,
  }
}

///|
pub fn FoldConfig::with_max_nodes(max_nodes : Int) -> FoldConfig {
  { ..FoldConfig::default(), max_nodes }
}
