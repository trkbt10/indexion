///|
/// Intermediate graph representation for flexible output formats.
/// Can be serialized to JSON and converted to Mermaid, SVG, DOT, etc.

///|
/// Node in the dependency graph.
pub struct GraphNode {
  id : String
  label : String
  kind : String // "internal", "external", "module", "function", "type"
  file : String? // source file path if available
  metadata : Map[String, String]
} derive(Eq)

///|
/// Edge in the dependency graph.
pub struct GraphEdge {
  from : String
  to : String
  kind : String // "dependency", "circular", "call", "extends", "implements"
  metadata : Map[String, String]
} derive(Eq)

///|
/// Intermediate graph representation.
pub struct GraphJSON {
  title : String
  nodes : Array[GraphNode]
  edges : Array[GraphEdge]
  metadata : Map[String, String]
}

///|
/// Creates a new empty GraphJSON.
pub fn GraphJSON::new(title? : String = "Graph") -> GraphJSON {
  { title, nodes: [], edges: [], metadata: Map::new() }
}

///|
/// Adds a node to the graph.
pub fn GraphJSON::add_node(
  self : GraphJSON,
  id : String,
  label : String,
  kind? : String = "module",
  file? : String? = None,
) -> Unit {
  self.nodes.push({ id, label, kind, file, metadata: Map::new() })
}

///|
/// Adds an edge to the graph.
pub fn GraphJSON::add_edge(
  self : GraphJSON,
  from : String,
  to : String,
  kind? : String = "dependency",
) -> Unit {
  self.edges.push({ from, to, kind, metadata: Map::new() })
}

///|
/// Converts GraphJSON to JSON value.
pub fn GraphJSON::to_json(self : GraphJSON) -> Json {
  let nodes_json : Array[Json] = []
  for node in self.nodes {
    let obj : Map[String, Json] = Map::new()
    obj.set("id", node.id.to_json())
    obj.set("label", node.label.to_json())
    obj.set("kind", node.kind.to_json())
    match node.file {
      Some(f) => obj.set("file", f.to_json())
      None => ()
    }
    if node.metadata.size() > 0 {
      let meta : Map[String, Json] = Map::new()
      for k, v in node.metadata {
        meta.set(k, v.to_json())
      }
      obj.set("metadata", Json::object(meta))
    }
    nodes_json.push(Json::object(obj))
  }
  let edges_json : Array[Json] = []
  for edge in self.edges {
    let obj : Map[String, Json] = Map::new()
    obj.set("from", edge.from.to_json())
    obj.set("to", edge.to.to_json())
    obj.set("kind", edge.kind.to_json())
    if edge.metadata.size() > 0 {
      let meta : Map[String, Json] = Map::new()
      for k, v in edge.metadata {
        meta.set(k, v.to_json())
      }
      obj.set("metadata", Json::object(meta))
    }
    edges_json.push(Json::object(obj))
  }
  let root : Map[String, Json] = Map::new()
  root.set("title", self.title.to_json())
  root.set("nodes", Json::array(nodes_json))
  root.set("edges", Json::array(edges_json))
  if self.metadata.size() > 0 {
    let meta : Map[String, Json] = Map::new()
    for k, v in self.metadata {
      meta.set(k, v.to_json())
    }
    root.set("metadata", Json::object(meta))
  }
  Json::object(root)
}

///|
/// Parses GraphJSON from JSON value.
pub fn GraphJSON::from_json(json : Json) -> GraphJSON? {
  match json {
    Object(obj) => {
      let title = match obj.get("title") {
        Some(String(s)) => s
        _ => "Graph"
      }
      let graph = GraphJSON::new(title~)
      // Parse nodes
      match obj.get("nodes") {
        Some(Array(nodes_arr)) =>
          for node_json in nodes_arr {
            match node_json {
              Object(node_obj) => {
                let id = match node_obj.get("id") {
                  Some(String(s)) => s
                  _ => continue
                }
                let label = match node_obj.get("label") {
                  Some(String(s)) => s
                  _ => id
                }
                let kind = match node_obj.get("kind") {
                  Some(String(s)) => s
                  _ => "module"
                }
                let file : String? = match node_obj.get("file") {
                  Some(String(s)) => Some(s)
                  _ => None
                }
                graph.nodes.push({ id, label, kind, file, metadata: Map::new() })
              }
              _ => ()
            }
          }
        _ => ()
      }
      // Parse edges
      match obj.get("edges") {
        Some(Array(edges_arr)) =>
          for edge_json in edges_arr {
            match edge_json {
              Object(edge_obj) => {
                let from = match edge_obj.get("from") {
                  Some(String(s)) => s
                  _ => continue
                }
                let to = match edge_obj.get("to") {
                  Some(String(s)) => s
                  _ => continue
                }
                let kind = match edge_obj.get("kind") {
                  Some(String(s)) => s
                  _ => "dependency"
                }
                graph.edges.push({ from, to, kind, metadata: Map::new() })
              }
              _ => ()
            }
          }
        _ => ()
      }
      Some(graph)
    }
    _ => None
  }
}

///|
/// Build GraphJSON from module dependencies.
pub fn build_graph_from_deps(
  deps : Array[@query.ModuleDep],
  circulars? : Array[@query.CircularDep] = [],
  graph? : @graph.CodeGraph = @graph.CodeGraph::new(),
  title? : String = "Module Dependencies",
) -> GraphJSON {
  let result = GraphJSON::new(title~)
  // Collect internal module IDs
  let internal_ids : Map[String, String] = Map::new() // id -> file
  let internal_paths : Array[Array[String]] = [] // for common prefix detection
  for entry in graph.get_modules() {
    let mod_info = entry.1
    match mod_info.file {
      Some(f) => {
        internal_ids.set(mod_info.id, f)
        let id_dir = strip_file_suffix(mod_info.id)
        internal_paths.push(split_by_char(id_dir, '/'))
      }
      None => ()
    }
  }
  // Compute common prefix across all internal modules
  let common_prefix = find_common_prefix(internal_paths)
  // Collect unique nodes
  let seen_nodes : Map[String, Bool] = Map::new()
  let node_labels : Map[String, String] = Map::new() // original -> label
  let mut id_counter = 0
  for dep in deps {
    for name in [dep.from, dep.to] {
      if not(seen_nodes.contains(name)) {
        seen_nodes.set(name, true)
        let node_id = "N" + id_counter.to_string()
        node_labels.set(name, node_id)
        id_counter = id_counter + 1
        // Determine if internal or external
        let (kind, file) : (String, String?) = match internal_ids.get(name) {
          Some(f) => ("internal", Some(f))
          None => {
            // Check if name matches any internal ID pattern
            let mut found : (String, String?)? = None
            for entry in internal_ids {
              let id_dir = strip_file_suffix(entry.0)
              if name == entry.0 ||
                name == id_dir ||
                name.has_suffix("/" + id_dir) {
                found = Some(("internal", Some(entry.1)))
                break
              }
            }
            match found {
              Some(f) => f
              None => ("external", None)
            }
          }
        }
        // Generate shortened label using common prefix for internal modules
        let label = if kind == "internal" {
          shorten_module_name(name, common_prefix~)
        } else {
          name
        }
        result.nodes.push({
          id: node_id,
          label,
          kind,
          file,
          metadata: Map::new(),
        })
      }
    }
  }
  // Add circular dependency nodes
  for circ in circulars {
    for name in [circ.from, circ.to] {
      if not(seen_nodes.contains(name)) {
        seen_nodes.set(name, true)
        let node_id = "N" + id_counter.to_string()
        node_labels.set(name, node_id)
        id_counter = id_counter + 1
        let (kind, file) : (String, String?) = match internal_ids.get(name) {
          Some(f) => ("internal", Some(f))
          None => ("external", None)
        }
        // Generate shortened label using common prefix for internal modules
        let label = if kind == "internal" {
          shorten_module_name(name, common_prefix~)
        } else {
          name
        }
        result.nodes.push({
          id: node_id,
          label,
          kind,
          file,
          metadata: Map::new(),
        })
      }
    }
  }
  // Add edges
  let seen_edges : Map[String, Bool] = Map::new()
  for dep in deps {
    let from_id = node_labels.get(dep.from).unwrap()
    let to_id = node_labels.get(dep.to).unwrap()
    let edge_key = from_id + "->" + to_id
    if not(seen_edges.contains(edge_key)) && from_id != to_id {
      seen_edges.set(edge_key, true)
      result.edges.push({
        from: from_id,
        to: to_id,
        kind: "dependency",
        metadata: Map::new(),
      })
    }
  }
  // Add circular edges
  for circ in circulars {
    let from_id = node_labels.get(circ.from).unwrap()
    let to_id = node_labels.get(circ.to).unwrap()
    let edge_key = from_id + "->circ->" + to_id
    if not(seen_edges.contains(edge_key)) && from_id != to_id {
      seen_edges.set(edge_key, true)
      result.edges.push({
        from: from_id,
        to: to_id,
        kind: "circular",
        metadata: Map::new(),
      })
    }
  }
  result
}
