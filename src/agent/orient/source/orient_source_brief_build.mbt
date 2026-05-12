///|
pub fn build_file_briefs(
  files : Array[@pipeline.SupportedFile],
  graph : @graph.CodeGraph,
  cached_map : AgentOrientMap?,
) -> Array[LocalFileBrief] {
  let symbols_by_module : Map[String, Array[String]] = {}
  for entry in graph.get_symbols() {
    let sym = entry.1
    let line = symbol_line(sym.name, sym.kind, sym.doc)
    match symbols_by_module.get(sym.module_id) {
      Some(arr) => arr.push(line)
      None => symbols_by_module.set(sym.module_id, [line])
    }
  }
  let dep_counts = internal_dependency_counts(files, graph)
  let external_terms = external_dependency_terms(files, graph)
  let result : Array[LocalFileBrief] = []
  for file in files {
    let source_hash = @cas_hash.compute_hash(file.content).to_string()
    match cached_file_for(file.path, source_hash, cached_map) {
      Some(cached) => {
        let summary = source_summary_for_cache(file, cached.structural_summary)
        result.push(
          new_local_file_brief(
            cached.path,
            cached.source_hash,
            cached.structural_summary,
            summary,
            role=cached.role,
          ),
        )
        continue
      }
      None => ()
    }
    let structural = structural_summary(file, graph, symbols_by_module)
    let text = source_summary_for_cache(file, structural)
    let structural_terms = task_tokens(structural)
    let summary_terms = task_tokens(text)
    let role = infer_file_role(
      file,
      structural_terms,
      summary_terms,
      internal_outgoing_count(dep_counts, file.path),
      internal_incoming_count(dep_counts, file.path),
      external_terms=external_terms.get(file.path).unwrap_or([]),
    )
    result.push(
      new_local_file_brief(
        file.path,
        source_hash,
        structural,
        text,
        role~,
        structural_terms~,
        summary_terms~,
      ),
    )
  }
  normalize_surface_owner_roles(result)
  result
}

///|
fn source_summary_for_cache(
  file : @pipeline.SupportedFile,
  structural : String,
) -> String {
  if keeps_full_source_summary(file) {
    let summary = StringBuilder::new()
    summary.write_string(structural)
    summary.write_string(file.content)
    summary.write_string("\n")
    summary.to_string()
  } else {
    bounded_source_preview(file.content, @cache.summary_preview_limit)
  }
}

///|
fn keeps_full_source_summary(file : @pipeline.SupportedFile) -> Bool {
  file.content_type == Some("document") || @map.is_documentation_path(file.path)
}

///|
fn bounded_source_preview(text : String, limit : Int) -> String {
  let limit = if limit < 0 { 0 } else { limit }
  let chars = text.to_array()
  if chars.length() <= limit {
    text
  } else {
    let preview = StringBuilder::new()
    for i in 0..<limit {
      preview.write_char(chars[i])
    }
    preview.to_string()
  }
}

///|
pub fn new_local_file_brief(
  path : String,
  source_hash : String,
  structural_summary : String,
  summary : String,
  role? : String = "implementation",
  structural_terms? : Array[String] = [],
  summary_terms? : Array[String] = [],
) -> LocalFileBrief {
  let structural_terms = if structural_terms.length() > 0 {
    structural_terms
  } else {
    task_tokens(structural_summary)
  }
  let summary_terms = if summary_terms.length() > 0 {
    summary_terms
  } else {
    task_tokens(summary)
  }
  {
    path,
    role,
    source_hash,
    structural_summary,
    summary,
    structural_terms,
    summary_terms,
    score: 0.0,
    matched_terms: [],
  }
}
