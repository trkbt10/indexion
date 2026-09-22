///|
pub fn internal_dependency_counts(
  files : Array[@pipeline.SupportedFile],
  graph : @graph.CodeGraph,
) -> Map[String, (Int, Int)] {
  let known : Map[String, Bool] = Map([])
  for file in files {
    known.set(file.path, true)
  }
  let counts : Map[String, (Int, Int)] = Map([])
  for edge in graph.get_edges() {
    if !(edge.kind is @graph.ModuleDependsOn) {
      continue
    }
    let from = graph_endpoint_file(edge.from, graph)
    let to = graph_endpoint_file(edge.to, graph)
    if from is None || to is None {
      continue
    }
    let from = from.unwrap()
    let to = to.unwrap()
    if from == to || !known.contains(from) || !known.contains(to) {
      continue
    }
    let from_counts = counts.get(from).unwrap_or((0, 0))
    counts.set(from, (from_counts.0 + 1, from_counts.1))
    let to_counts = counts.get(to).unwrap_or((0, 0))
    counts.set(to, (to_counts.0, to_counts.1 + 1))
  }
  counts
}

///|
pub fn external_dependency_terms(
  files : Array[@pipeline.SupportedFile],
  graph : @graph.CodeGraph,
) -> Map[String, Array[String]] {
  let known : Map[String, Bool] = Map([])
  for file in files {
    known.set(file.path, true)
  }
  let result : Map[String, Array[String]] = Map([])
  for edge in graph.get_edges() {
    if !(edge.kind is @graph.ModuleDependsOn) {
      continue
    }
    let from = graph_endpoint_file(edge.from, graph)
    if from is None {
      continue
    }
    let from = from.unwrap()
    if !known.contains(from) || graph_endpoint_file(edge.to, graph) is Some(_) {
      continue
    }
    let terms = task_tokens(edge.attrs.get("via").unwrap_or(edge.to))
    match result.get(from) {
      Some(arr) =>
        for term in terms {
          if !arr.contains(term) {
            arr.push(term)
          }
        }
      None => result.set(from, terms)
    }
  }
  result
}

///|
pub fn normalize_surface_owner_roles(briefs : Array[LocalFileBrief]) -> Unit {
  let cli_dirs : Array[String] = []
  for brief in briefs {
    if role_is_cli_consumer(brief.role) {
      let dir = owner_dir(brief.path)
      if !cli_dirs.contains(dir) {
        cli_dirs.push(dir)
      }
    }
  }
  if cli_dirs.is_empty() {
    return
  }
  for i = 0; i < briefs.length(); i = i + 1 {
    let brief = briefs[i]
    if cli_dirs.contains(owner_dir(brief.path)) &&
      !role_is_documentation(brief.role) {
      briefs[i] = { ..brief, role: "cli-consumer", }
    }
  }
}
