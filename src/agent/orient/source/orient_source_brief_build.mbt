///|
pub fn build_file_briefs(
  files : Array[@pipeline.SupportedFile],
  graph : @graph.CodeGraph,
  cached_map : AgentOrientMap?,
) -> Array[LocalFileBrief] {
  // Index the cached map by path once so per-file lookup is O(1). The legacy
  // `cached_file_for` helper scans the entire array per call, which collapses
  // into O(N²) and dominates orient update time on large repos.
  let cached_by_path : Map[String, AgentOrientMapFile] = {}
  match cached_map {
    Some(map) =>
      for entry in map.files {
        cached_by_path.set(entry.path, entry)
      }
    None => ()
  }
  // Hash once per file. We need the hash both for the dirty check (to decide
  // whether the expensive graph-derived signal maps are needed at all) and
  // for the per-file cache-or-rebuild decision below; computing it twice
  // doubles the hashing cost over the whole tree.
  let source_hashes : Array[String] = []
  let mut has_dirty_file = false
  for file in files {
    let hash = @cas_hash.compute_hash(file.content).to_string()
    source_hashes.push(hash)
    if !has_dirty_file {
      match cached_by_path.get(file.path) {
        Some(cached) if cached.source_hash == hash => ()
        _ => has_dirty_file = true
      }
    }
  }
  // The graph-derived signals are only consulted on the rebuild path. Avoid
  // paying for them when every discovered file already has a cached brief.
  let symbols_by_module : Map[String, Array[String]] = {}
  let dep_counts : Map[String, (Int, Int)] = if has_dirty_file {
    for entry in graph.get_symbols() {
      let sym = entry.1
      let line = symbol_line(sym.name, sym.kind, sym.doc)
      match symbols_by_module.get(sym.module_id) {
        Some(arr) => arr.push(line)
        None => symbols_by_module.set(sym.module_id, [line])
      }
    }
    internal_dependency_counts(files, graph)
  } else {
    {}
  }
  let external_terms : Map[String, Array[String]] = if has_dirty_file {
    external_dependency_terms(files, graph)
  } else {
    {}
  }
  let result : Array[LocalFileBrief] = []
  for i = 0; i < files.length(); i = i + 1 {
    let file = files[i]
    let source_hash = source_hashes[i]
    match cached_by_path.get(file.path) {
      Some(cached) if cached.source_hash == source_hash => {
        let summary = source_summary_for_cache(file, cached.structural_summary)
        result.push(
          cached_local_file_brief(
            cached.path,
            cached.source_hash,
            cached.structural_summary,
            summary,
            cached.role,
          ),
        )
        continue
      }
      _ => ()
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
  // Avoid materializing the full content as a char array just to read the
  // first `limit` code points — that turns the per-file cached path into an
  // O(file size) allocation across every refresh and dominated orient time
  // on large repos.
  let preview = StringBuilder::new()
  let mut written = 0
  for c in text {
    if written >= limit {
      return preview.to_string()
    }
    preview.write_char(c)
    written = written + 1
  }
  text
}

///|
/// Build a `LocalFileBrief` for a path whose source content hash matches the
/// vcdb cache, skipping the expensive `task_tokens` pass over both the
/// structural summary and the source preview.
///
/// The terms are unused on the orient update path (vcdb attrs and the
/// embedding both consume the plain text), and skipping them per file is the
/// difference between O(content) and O(1) per cached entry — which dominates
/// orient runtime on large repos.
pub fn cached_local_file_brief(
  path : String,
  source_hash : String,
  structural_summary : String,
  summary : String,
  role : String,
  mtime_ns? : Int64 = 0L,
  size_bytes? : Int64 = 0L,
) -> LocalFileBrief {
  {
    path,
    role,
    source_hash,
    structural_summary,
    summary,
    structural_terms: [],
    summary_terms: [],
    score: 0.0,
    matched_terms: [],
    mtime_ns,
    size_bytes,
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
  mtime_ns? : Int64 = 0L,
  size_bytes? : Int64 = 0L,
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
    mtime_ns,
    size_bytes,
  }
}
