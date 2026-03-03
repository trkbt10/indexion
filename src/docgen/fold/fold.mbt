// Recursive graph folding: simplify dependency graphs by collapsing
// low-importance nodes into clusters.

///|
/// Fold a CodeGraph into a simplified FoldedGraph.
/// Uses importance scoring to decide which nodes to preserve and which
/// to collapse into clusters. Applies folding recursively until the
/// target node count is reached or max depth is exhausted.
pub fn fold_graph(graph : @graph.CodeGraph, config : FoldConfig) -> FoldedGraph {
  // Score modules by importance
  let scores = score_modules(graph, config)
  // Extract module-level edges
  let deps = @query.extract_module_deps(graph)
  // Build initial node set and edge set
  let initial_nodes : Map[String, FoldedNode] = {}
  for imp in scores {
    initial_nodes.set(imp.id, FoldedNode::Single(imp.id, imp.score))
  }
  let initial_edges : Array[FoldedEdge] = []
  for dep in deps {
    initial_edges.push(FoldedEdge::new(dep.from, dep.to, 1))
  }
  let initial = FoldedGraph::new(initial_nodes, initial_edges, 0)
  // Recursively fold
  fold_recursive(initial, scores, config, 0)
}

///|
/// Fold a CodeGraph at the symbol level.
/// Collapses less important symbols within modules into clusters.
pub fn fold_graph_symbols(
  graph : @graph.CodeGraph,
  config : FoldConfig,
) -> FoldedGraph {
  let scores = score_symbols(graph, config)
  let calls = @query.extract_call_graph(graph)
  let initial_nodes : Map[String, FoldedNode] = {}
  for imp in scores {
    initial_nodes.set(imp.id, FoldedNode::Single(imp.id, imp.score))
  }
  let initial_edges : Array[FoldedEdge] = []
  for call in calls {
    initial_edges.push(FoldedEdge::new(call.caller, call.callee, 1))
  }
  let initial = FoldedGraph::new(initial_nodes, initial_edges, 0)
  fold_recursive(initial, scores, config, 0)
}

///|
/// Recursive folding pass.
/// Each pass collapses nodes below the threshold into clusters,
/// then re-evaluates if more folding is needed.
fn fold_recursive(
  current : FoldedGraph,
  scores : Array[NodeImportance],
  config : FoldConfig,
  depth : Int,
) -> FoldedGraph {
  // Stop conditions
  if depth >= config.max_depth {
    return current
  }
  if current.node_count() <= config.max_nodes {
    return current
  }
  // Partition nodes: keep important ones, fold the rest
  let keep : Map[String, FoldedNode] = {}
  let to_fold : Array[(String, FoldedNode)] = []
  // Build a score lookup from the original scores
  let score_map : Map[String, Double] = {}
  for imp in scores {
    score_map.set(imp.id, imp.score)
  }
  // Also compute effective scores for clusters
  for entry in current.nodes {
    let node_id = entry.0
    let node = entry.1
    let effective_score = match node {
      Single(_, s) => s
      Cluster(_, _, members) => {
        // Cluster score = max score of its members
        let mut max_s = 0.0
        for m in members {
          let s = score_map.get(m).unwrap_or(0.0)
          if s > max_s {
            max_s = s
          }
        }
        max_s
      }
    }
    if effective_score >= compute_adaptive_threshold(current, config) {
      keep.set(node_id, node)
    } else {
      to_fold.push((node_id, node))
    }
  }
  // If nothing to fold, we're done
  if to_fold.length() == 0 {
    return current
  }
  // Group nodes to fold by proximity (shared edges)
  let clusters = build_clusters(to_fold, current.edges, keep)
  // Merge clusters into the kept node set
  let new_nodes : Map[String, FoldedNode] = {}
  for entry in keep {
    new_nodes.set(entry.0, entry.1)
  }
  for cluster in clusters {
    new_nodes.set(cluster.0, cluster.1)
  }
  // Remap edges
  let new_edges = remap_edges(current.edges, new_nodes, clusters)
  let folded = FoldedGraph::new(new_edges.0, new_edges.1, depth + 1)
  // Recurse if still too many nodes
  if folded.node_count() > config.max_nodes {
    fold_recursive(folded, scores, config, depth + 1)
  } else {
    folded
  }
}

///|
/// Compute an adaptive threshold that increases with each folding pass.
/// As the graph gets larger relative to max_nodes, the threshold rises.
fn compute_adaptive_threshold(
  current : FoldedGraph,
  config : FoldConfig,
) -> Double {
  let ratio = config.max_nodes.to_double() / current.node_count().to_double()
  // Clamp ratio to [0, 1]
  let clamped = if ratio > 1.0 {
    1.0
  } else if ratio < 0.0 {
    0.0
  } else {
    ratio
  }
  // Threshold increases as we need to fold more
  // When ratio is small (many nodes), threshold is higher
  config.threshold + (1.0 - clamped) * (1.0 - config.threshold) * 0.5
}

///|
/// Build clusters from nodes that need folding.
/// Groups nodes by their connectivity to kept nodes.
fn build_clusters(
  to_fold : Array[(String, FoldedNode)],
  edges : Array[FoldedEdge],
  keep : Map[String, FoldedNode],
) -> Array[(String, FoldedNode)] {
  if to_fold.length() == 0 {
    return []
  }
  // Build adjacency: for each to-fold node, find which kept nodes it connects to
  let neighbors : Map[String, String] = {}
  for pair in to_fold {
    let node_id = pair.0
    // Find the most connected kept neighbor
    let mut best_neighbor = ""
    let mut best_count = 0
    let neighbor_counts : Map[String, Int] = {}
    for edge in edges {
      if edge.from == node_id && keep.contains(edge.to) {
        let c = neighbor_counts.get(edge.to).unwrap_or(0) + edge.weight
        neighbor_counts.set(edge.to, c)
        if c > best_count {
          best_count = c
          best_neighbor = edge.to
        }
      }
      if edge.to == node_id && keep.contains(edge.from) {
        let c = neighbor_counts.get(edge.from).unwrap_or(0) + edge.weight
        neighbor_counts.set(edge.from, c)
        if c > best_count {
          best_count = c
          best_neighbor = edge.from
        }
      }
    }
    if best_neighbor.length() > 0 {
      neighbors.set(node_id, best_neighbor)
    }
  }
  // Group by neighbor
  let groups : Map[String, Array[String]] = {}
  let ungrouped : Array[String] = []
  for pair in to_fold {
    let node_id = pair.0
    match neighbors.get(node_id) {
      Some(neighbor) =>
        match groups.get(neighbor) {
          Some(arr) => arr.push(node_id)
          None => groups.set(neighbor, [node_id])
        }
      None => ungrouped.push(node_id)
    }
  }
  // Create cluster nodes
  let result : Array[(String, FoldedNode)] = []
  for entry in groups {
    let neighbor_id = entry.0
    let members = entry.1
    let all_members = collect_leaf_members_from_ids(members, to_fold)
    let cluster_id = "cluster_" + neighbor_id
    let label = shorten_name(neighbor_id) + " group"
    result.push(
      (
        cluster_id,
        FoldedNode::Cluster(label, all_members.length(), all_members),
      ),
    )
  }
  // Ungrouped nodes form a single "other" cluster
  if ungrouped.length() > 0 {
    let all_members = collect_leaf_members_from_ids(ungrouped, to_fold)
    result.push(
      (
        "cluster_other",
        FoldedNode::Cluster("other", all_members.length(), all_members),
      ),
    )
  }
  result
}

///|
/// Collect all leaf member IDs from a set of node IDs,
/// expanding any existing clusters.
fn collect_leaf_members_from_ids(
  ids : Array[String],
  all_nodes : Array[(String, FoldedNode)],
) -> Array[String] {
  let result : Array[String] = []
  let node_map : Map[String, FoldedNode] = {}
  for pair in all_nodes {
    node_map.set(pair.0, pair.1)
  }
  for id in ids {
    match node_map.get(id) {
      Some(FoldedNode::Single(real_id, _)) => result.push(real_id)
      Some(FoldedNode::Cluster(_, _, members)) =>
        for m in members {
          result.push(m)
        }
      None => result.push(id)
    }
  }
  result
}

///|
/// Remap edges after folding: redirect edges to/from folded nodes
/// to their cluster, and deduplicate.
fn remap_edges(
  old_edges : Array[FoldedEdge],
  new_nodes : Map[String, FoldedNode],
  clusters : Array[(String, FoldedNode)],
) -> (Map[String, FoldedNode], Array[FoldedEdge]) {
  // Build reverse mapping: member_id -> cluster_id
  let old_to_new : Map[String, String] = {}
  for cluster in clusters {
    let cluster_id = cluster.0
    match cluster.1 {
      Cluster(_, _, members) =>
        for m in members {
          old_to_new.set(m, cluster_id)
        }
      _ => ()
    }
  }
  // Remap edges
  let edge_map : Map[String, Int] = {}
  let result_edges : Array[FoldedEdge] = []
  for edge in old_edges {
    let from = old_to_new.get(edge.from).unwrap_or(edge.from)
    let to = old_to_new.get(edge.to).unwrap_or(edge.to)
    // Skip self-loops created by folding
    if from == to {
      continue
    }
    // Skip edges where endpoints don't exist in new nodes
    if not(new_nodes.contains(from)) || not(new_nodes.contains(to)) {
      continue
    }
    // Deduplicate by merging weights
    let key = from + " -> " + to
    match edge_map.get(key) {
      Some(idx) => {
        let existing = result_edges[idx]
        result_edges[idx] = FoldedEdge::new(
          from,
          to,
          existing.weight + edge.weight,
        )
      }
      None => {
        edge_map.set(key, result_edges.length())
        result_edges.push(FoldedEdge::new(from, to, edge.weight))
      }
    }
  }
  (new_nodes, result_edges)
}

///|
fn shorten_name(name : String) -> String {
  let chars = name.to_array()
  // Find last '/' or '::'
  let mut last_sep = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last_sep = i
    }
    if i + 1 < chars.length() && chars[i] == ':' && chars[i + 1] == ':' {
      last_sep = i + 1
    }
  }
  if last_sep >= 0 && last_sep + 1 < chars.length() {
    let result : Array[Char] = []
    for i = last_sep + 1; i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    name
  }
}
