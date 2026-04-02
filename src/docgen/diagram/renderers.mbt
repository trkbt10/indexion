///|
/// Renderers for converting GraphJSON to various output formats.

///|
/// Render GraphJSON to Mermaid format.
pub fn render_mermaid(graph : GraphJSON) -> String {
  let lines : Array[String] = []
  lines.push("```mermaid")
  lines.push("---")
  lines.push("title: " + graph.title)
  lines.push("---")
  lines.push("graph LR")
  // Node definitions
  for node in graph.nodes {
    let escaped = escape_mermaid(node.label)
    lines.push("  " + node.id + "[" + escaped + "]")
  }
  // Edge definitions
  let circ_indices : Array[Int] = []
  let mut edge_idx = 0
  for edge in graph.edges {
    if edge.kind == "circular" {
      lines.push("  " + edge.from + " -.->|circular| " + edge.to)
      circ_indices.push(edge_idx)
    } else {
      lines.push("  " + edge.from + " --> " + edge.to)
    }
    edge_idx = edge_idx + 1
  }
  // Style circular edges
  if circ_indices.length() > 0 {
    lines.push("  linkStyle default stroke:#333")
    for idx in circ_indices {
      lines.push(
        "  linkStyle " +
        idx.to_string() +
        " stroke:red,stroke-width:2px,stroke-dasharray:5",
      )
    }
  }
  lines.push("```")
  lines.join("\n")
}

///|
/// Render GraphJSON to DOT (Graphviz) format.
pub fn render_dot(graph : GraphJSON) -> String {
  let lines : Array[String] = []
  lines.push("digraph G {")
  lines.push("  rankdir=LR;")
  lines.push("  label=\"" + escape_dot(graph.title) + "\";")
  lines.push("  labelloc=t;")
  lines.push("")
  // Node definitions
  for node in graph.nodes {
    let style = if node.kind == "external" {
      "style=dashed"
    } else {
      "style=solid"
    }
    lines.push(
      "  " +
      node.id +
      " [label=\"" +
      escape_dot(node.label) +
      "\" " +
      style +
      "];",
    )
  }
  lines.push("")
  // Edge definitions
  for edge in graph.edges {
    let style = if edge.kind == "circular" {
      " [style=dashed color=red label=\"circular\"]"
    } else {
      ""
    }
    lines.push("  " + edge.from + " -> " + edge.to + style + ";")
  }
  lines.push("}")
  lines.join("\n")
}

///|
/// Render GraphJSON to D2 format.
pub fn render_d2(graph : GraphJSON) -> String {
  let lines : Array[String] = []
  lines.push("title: " + graph.title)
  lines.push("")
  // Node definitions with labels
  for node in graph.nodes {
    let style = if node.kind == "external" {
      ".style.stroke-dash: 3"
    } else {
      ""
    }
    lines.push(node.id + ": " + escape_d2(node.label) + " {")
    if style.length() > 0 {
      lines.push("  " + style)
    }
    lines.push("}")
  }
  lines.push("")
  // Edge definitions
  for edge in graph.edges {
    if edge.kind == "circular" {
      lines.push(
        edge.from +
        " -> " +
        edge.to +
        ": circular { style.stroke: red; style.stroke-dash: 3 }",
      )
    } else {
      lines.push(edge.from + " -> " + edge.to)
    }
  }
  lines.join("\n")
}

///|
/// Render GraphJSON to plain text adjacency list.
pub fn render_text(graph : GraphJSON) -> String {
  let lines : Array[String] = []
  lines.push("# " + graph.title)
  lines.push("")
  // Build adjacency map
  let adj : Map[String, Array[String]] = Map::new()
  let labels : Map[String, String] = Map::new()
  for node in graph.nodes {
    labels.set(node.id, node.label)
    adj.set(node.id, [])
  }
  for edge in graph.edges {
    match adj.get(edge.from) {
      Some(arr) => arr.push(edge.to)
      None => ()
    }
  }
  // Output
  for node in graph.nodes {
    let deps = adj.get(node.id).unwrap()
    if deps.length() > 0 {
      let dep_labels : Array[String] = []
      for dep_id in deps {
        dep_labels.push(labels.get(dep_id).unwrap_or(dep_id))
      }
      lines.push(node.label + " -> " + dep_labels.join(", "))
    } else {
      lines.push(node.label + " (no dependencies)")
    }
  }
  lines.join("\n")
}

// Helper functions

///|
fn escape_dot(s : String) -> String {
  let result : Array[Char] = []
  for c in s {
    match c {
      '"' => {
        result.push('\\')
        result.push('"')
      }
      '\\' => {
        result.push('\\')
        result.push('\\')
      }
      _ => result.push(c)
    }
  }
  String::from_array(result)
}

///|
fn escape_d2(s : String) -> String {
  // D2 uses | for multi-line, escape special chars
  let result : Array[Char] = []
  for c in s {
    match c {
      '|' | '{' | '}' => {
        result.push('\\')
        result.push(c)
      }
      _ => result.push(c)
    }
  }
  String::from_array(result)
}
