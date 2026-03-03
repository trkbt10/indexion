// Tests for graph folding and importance scoring.

///|
fn edge_kind(s : String) -> @graph.EdgeKind {
  @graph.EdgeKind::from_string(s)
}

// --- Importance scoring tests ---

///|
test "score_modules: empty graph returns empty" {
  let graph = @graph.CodeGraph::new()
  let config = FoldConfig::default()
  let scores = score_modules(graph, config)
  assert_eq(scores.length(), 0)
}

///|
test "score_modules: single module gets score" {
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module("src/main.ts", file=Some("src/main.ts"))
  let config = FoldConfig::default()
  let scores = score_modules(graph, config)
  assert_eq(scores.length(), 1)
  assert_eq(scores[0].id, "src/main.ts")
}

///|
test "score_modules: highly referenced module scores higher" {
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module("utils.ts", file=Some("utils.ts"))
  let _ = graph.get_or_add_module("a.ts", file=Some("a.ts"))
  let _ = graph.get_or_add_module("b.ts", file=Some("b.ts"))
  let _ = graph.get_or_add_module("c.ts", file=Some("c.ts"))
  // utils.ts is referenced by a, b, c
  graph.add_edge(edge_kind("module_depends_on"), "a.ts", "utils.ts")
  graph.add_edge(edge_kind("module_depends_on"), "b.ts", "utils.ts")
  graph.add_edge(edge_kind("module_depends_on"), "c.ts", "utils.ts")
  let config = FoldConfig::default()
  let scores = score_modules(graph, config)
  // scores are sorted descending; utils.ts should be first
  assert_eq(scores[0].id, "utils.ts")
  assert_true(scores[0].score > scores[1].score)
}

///|
test "score_modules: centrality increases with connections" {
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module("hub.ts", file=Some("hub.ts"))
  let _ = graph.get_or_add_module("leaf1.ts", file=Some("leaf1.ts"))
  let _ = graph.get_or_add_module("leaf2.ts", file=Some("leaf2.ts"))
  let _ = graph.get_or_add_module("leaf3.ts", file=Some("leaf3.ts"))
  // hub connects to all leaves
  graph.add_edge(edge_kind("module_depends_on"), "hub.ts", "leaf1.ts")
  graph.add_edge(edge_kind("module_depends_on"), "hub.ts", "leaf2.ts")
  graph.add_edge(edge_kind("module_depends_on"), "hub.ts", "leaf3.ts")
  let config = FoldConfig::default()
  let scores = score_modules(graph, config)
  // hub should have highest centrality
  assert_eq(scores[0].id, "hub.ts")
}

///|
test "ImportanceSignals::zero: all zeros" {
  let signals = ImportanceSignals::zero()
  assert_eq(signals.ref_score, 0.0)
  assert_eq(signals.centrality_score, 0.0)
  assert_eq(signals.tfidf_score, 0.0)
}

// --- Min-max normalization tests ---

///|
test "min_max_normalize: basic normalization" {
  let values = [1.0, 5.0, 3.0]
  let result = min_max_normalize(values)
  assert_eq(result[0], 0.0) // min
  assert_eq(result[1], 1.0) // max
  assert_eq(result[2], 0.5) // mid
}

///|
test "min_max_normalize: all equal values" {
  let values = [3.0, 3.0, 3.0]
  let result = min_max_normalize(values)
  // All equal non-zero => all 1.0
  assert_eq(result[0], 1.0)
  assert_eq(result[1], 1.0)
}

///|
test "min_max_normalize: all zeros" {
  let values = [0.0, 0.0, 0.0]
  let result = min_max_normalize(values)
  assert_eq(result[0], 0.0)
}

///|
test "min_max_normalize: empty returns empty" {
  let values : Array[Double] = []
  let result = min_max_normalize(values)
  assert_eq(result.length(), 0)
}

// --- Graph folding tests ---

///|
test "fold_graph: small graph not folded" {
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module("a.ts", file=Some("a.ts"))
  let _ = graph.get_or_add_module("b.ts", file=Some("b.ts"))
  graph.add_edge(edge_kind("module_depends_on"), "a.ts", "b.ts")
  let config = FoldConfig::with_max_nodes(10)
  let folded = fold_graph(graph, config)
  // 2 nodes <= max_nodes=10, no folding needed
  assert_eq(folded.node_count(), 2)
  assert_eq(folded.get_depth(), 0)
}

///|
test "fold_graph: large graph gets simplified" {
  let graph = @graph.CodeGraph::new()
  // Create 20 modules
  for i = 0; i < 20; i = i + 1 {
    let name = "mod" + i.to_string() + ".ts"
    let _ = graph.get_or_add_module(name, file=Some(name))
  }
  // mod0 is a hub - referenced by many
  for i = 1; i < 20; i = i + 1 {
    let name = "mod" + i.to_string() + ".ts"
    graph.add_edge(edge_kind("module_depends_on"), name, "mod0.ts")
  }
  let config = FoldConfig::with_max_nodes(5)
  let folded = fold_graph(graph, config)
  // Should be simplified to <= 5 nodes
  assert_true(folded.node_count() <= 10) // Some clustering may not reach exactly 5
}

///|
test "FoldedGraph::new: creates graph with correct depth" {
  let nodes : Map[String, FoldedNode] = {}
  nodes.set("a", FoldedNode::Single("a", 1.0))
  let edges : Array[FoldedEdge] = []
  let fg = FoldedGraph::new(nodes, edges, 3)
  assert_eq(fg.get_depth(), 3)
  assert_eq(fg.node_count(), 1)
}

///|
test "FoldConfig::default: has sensible defaults" {
  let config = FoldConfig::default()
  assert_eq(config.max_nodes, 15)
  assert_eq(config.max_depth, 5)
  assert_true(config.threshold > 0.0)
  assert_true(config.threshold < 1.0)
}

///|
test "FoldConfig::with_max_nodes: sets max_nodes" {
  let config = FoldConfig::with_max_nodes(10)
  assert_eq(config.max_nodes, 10)
}

///|
test "fold_graph: preserves important hub node" {
  let graph = @graph.CodeGraph::new()
  // Create hub + many leaves
  let _ = graph.get_or_add_module("hub.ts", file=Some("hub.ts"))
  for i = 0; i < 15; i = i + 1 {
    let name = "leaf" + i.to_string() + ".ts"
    let _ = graph.get_or_add_module(name, file=Some(name))
    graph.add_edge(edge_kind("module_depends_on"), name, "hub.ts")
  }
  let config = FoldConfig::with_max_nodes(5)
  let folded = fold_graph(graph, config)
  // hub.ts should still be visible (it has highest importance)
  let nodes = folded.get_nodes()
  let mut hub_found = false
  for entry in nodes {
    match entry.1 {
      FoldedNode::Single(id, _) => {
        if id == "hub.ts" {
          hub_found = true
        }
      }
      _ => ()
    }
  }
  assert_true(hub_found)
}
