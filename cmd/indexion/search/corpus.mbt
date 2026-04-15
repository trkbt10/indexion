///|
/// # Corpus Construction
///
/// Discovers files, classifies them by KGF spec characteristics,
/// and builds SearchDocuments. No hardcoded file extensions or content types.

///|
/// Build a search corpus from the given paths.
/// Classifies files using KGF spec features: specs with content_type: document
/// are indexed by section splitting, others by function extraction.
pub fn build_corpus(
  paths : Array[String],
  config : SearchConfig,
) -> Array[@search_engine.SearchDocument] {
  let documents : Array[@search_engine.SearchDocument] = []
  // 1. Detect wiki directories among paths (contain wiki.json)
  let wiki_paths : Array[String] = []
  let file_paths : Array[String] = []
  for path in paths {
    let resolved = resolve_wiki_path(path)
    if is_wiki_dir(resolved) {
      wiki_paths.push(resolved)
    } else {
      file_paths.push(path)
    }
  }
  // 2. Load KGF registry (shared by wiki and file corpus)
  let all_target_dirs = if file_paths.length() > 0 { file_paths } else { ["."] }
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dirs=all_target_dirs,
  )
  // 3. Build wiki corpus
  for wiki_dir in wiki_paths {
    extract_wiki_documents(wiki_dir, registry, documents)
  }
  // 4. Discover files from non-wiki paths
  if file_paths.length() > 0 {
    let kgf_ignore = match registry {
      Some(reg) => reg.collect_ignore_patterns()
      None => []
    }
    let opts = @pipeline.DiscoverOptions::new(
      root_dir=@pipeline.root_dir_from_paths(file_paths),
      recursive=true,
      includes=config.includes,
      excludes=config.excludes,
      include_hidden=true,
      kgf_ignore~,
    )
    let supported = match registry {
      Some(reg) => @pipeline.collect_supported_file_info(file_paths, opts, reg)
      None => []
    }
    // 4. Classify by KGF spec content type.
    let code_files : Array[(String, String)] = []
    let structured_files : Array[(String, String, String)] = []
    for file in supported {
      match file.content_type {
        Some(content_type) =>
          structured_files.push((file.path, file.content, content_type))
        None => code_files.push((file.path, file.content))
      }
    }
    // 5. Build code documents via KGF function extraction (lightweight).
    //    Graph construction (build_graph_from_source) is too expensive for
    //    search — caller/callee counts do not justify a full rebuild.
    //    If a pre-built graph is needed, the serve layer can supply it
    //    separately via build_corpus_with_graph().
    if code_files.length() > 0 {
      let code_docs = @grep.extract_code_documents(code_files, registry)
      for doc in code_docs {
        documents.push(doc)
      }
      // Also emit file-level summary documents so broad queries
      // match files by path and symbol names.
      extract_code_file_documents(code_files, registry, documents)
    }
    // 6. Build structured documents.
    for file in structured_files {
      let (path, content, content_type) = file
      extract_structured_documents(
        path, content, content_type, registry, documents,
      )
    }
  }
  documents
}

///|
fn graph_target_dir(paths : Array[String]) -> String {
  if paths.is_empty() {
    return "."
  }
  let normalized : Array[String] = []
  for path in paths {
    let candidate = if (@fs.is_dir(path) catch { _ => false }) {
      path
    } else {
      @config.dirname(path)
    }
    normalized.push(if candidate.length() == 0 { "." } else { candidate })
  }
  let mut prefix = normalized[0]
  for path in normalized {
    prefix = common_dir_prefix(prefix, path)
    if prefix == "." {
      return "."
    }
  }
  if prefix.length() == 0 {
    "."
  } else {
    prefix
  }
}

///|
fn common_dir_prefix(left : String, right : String) -> String {
  let absolute = left.has_prefix("/") && right.has_prefix("/")
  let lhs = @common.split_by_char(left, '/')
  let rhs = @common.split_by_char(right, '/')
  let shared : Array[String] = []
  let limit = if lhs.length() < rhs.length() {
    lhs.length()
  } else {
    rhs.length()
  }
  let mut i = 0
  while i < limit {
    if lhs[i] != rhs[i] {
      break
    }
    shared.push(lhs[i])
    i += 1
  }
  if shared.is_empty() {
    if absolute {
      "/"
    } else {
      "."
    }
  } else {
    let joined = shared.join("/")
    if absolute {
      "/" + joined
    } else {
      joined
    }
  }
}

///|
/// Check if a directory contains wiki manifest (wiki content).
fn is_wiki_dir(path : String) -> Bool {
  @fs.path_exists(@wiki_types.wiki_manifest_path(path))
}

///|
/// Try to load a pre-built wiki search index from vectors.db + sections JSON.
/// Returns Some(WikiSearchIndex) when the path is a single wiki directory with
/// a persisted index; None otherwise (caller should fall back to build_corpus).
pub fn load_prebuilt_wiki_index(
  paths : Array[String],
) -> @wiki_search.WikiSearchIndex? {
  // Only applies when the sole target is a wiki directory
  if paths.length() != 1 {
    return None
  }
  let resolved = resolve_wiki_path(paths[0])
  if !is_wiki_dir(resolved) {
    return None
  }
  if !@wiki_search.exists(resolved) {
    return None
  }
  @wiki_search.load(resolved)
}

///|
/// Resolve wiki path — if it's `.indexion/wiki`, resolve via config.
fn resolve_wiki_path(path : String) -> String {
  if path.has_suffix(".indexion/wiki") || path.has_suffix(".indexion/wiki/") {
    let base = if path.has_suffix(".indexion/wiki/") {
      @common.substring(path, 0, path.to_array().length() - 15)
    } else {
      @common.substring(path, 0, path.to_array().length() - 14)
    }
    let resolved_base = if base.length() == 0 { "." } else { base }
    match @config.resolve_project_indexion_dir(resolved_base, "wiki") {
      Some(dir) => dir
      None => path
    }
  } else {
    path
  }
}

///|
/// Extract SearchDocuments from wiki pages.
fn extract_wiki_documents(
  wiki_dir : String,
  registry : @kgf_registry.KGFRegistry?,
  out : Array[@search_engine.SearchDocument],
) -> Unit {
  let data = match @wiki_interop.load_wiki_auto(wiki_dir) {
    Some(d) => d
    None => return
  }
  for entry in data.pages {
    let page_id = entry.0
    let page = entry.1
    let page_file = if page.file.length() > 0 {
      page.file
    } else {
      page_id + ".md"
    }
    let page_path = @config.join_path(wiki_dir, page_file)
    let lang = match registry {
      Some(reg) =>
        match reg.detect_from_path(page_path) {
          Some(l) => l
          None => ""
        }
      None => ""
    }
    let sections = @wiki_search.extract_sections(
      page_id,
      page.title,
      page.content,
      path=page_path,
      registry~,
    )
    for section in sections {
      let kind_str = if section.level == 1 { "page" } else { "section" }
      let doc_attrs : Map[String, String] = {}
      doc_attrs["node_type"] = @kgf_features.node_type_document
      doc_attrs["node_kind"] = kind_str
      doc_attrs["parent"] = page_id
      if lang.length() > 0 {
        doc_attrs["language"] = lang
      }
      out.push({
        id: section.id,
        text: section.title + " " + section.content,
        title: section.title,
        source: page_path,
        line: 0,
        kind: kind_str,
        attrs: doc_attrs,
      })
    }
  }
}

///|
/// Extract SearchDocuments from a structured file using KGF tokenization.
/// Files with `section_token` are split into sections; everything else is indexed
/// as a single file-sized document.
fn extract_structured_documents(
  path : String,
  content : String,
  content_type : String,
  registry : @kgf_registry.KGFRegistry?,
  out : Array[@search_engine.SearchDocument],
) -> Unit {
  let reg = match registry {
    Some(r) => r
    None => {
      push_whole_file_document(path, content, "", content_type, out)
      return
    }
  }
  let spec = match reg.detect_from_path(path) {
    Some(lang) => reg.get_spec(lang)
    None => {
      push_whole_file_document(path, content, "", content_type, out)
      return
    }
  }
  let tokens = match @kgf_features.tokenize_source(content, path, registry) {
    Some(toks) => toks
    None => {
      let lang = match reg.detect_from_path(path) {
        Some(value) => value
        None => ""
      }
      push_whole_file_document(path, content, lang, content_type, out)
      return
    }
  }
  let lang = match reg.detect_from_path(path) {
    Some(l) => l
    None => ""
  }
  let raw_sections = @doc_structure.extract_document_sections(
    tokens,
    content,
    spec~,
    path~,
  )
  if raw_sections.length() == 0 {
    push_whole_file_document(path, content, lang, content_type, out)
    return
  }
  let file_id = path
  let file_title = @config.basename(path)
  for idx, section in raw_sections {
    let id = if idx == 0 {
      file_id
    } else {
      file_id + "#section-" + (idx + 1).to_string()
    }
    let level = section.level.unwrap_or(if idx == 0 { 1 } else { 2 })
    let kind_str = if level == 1 { "page" } else { "section" }
    let doc_attrs : Map[String, String] = {}
    doc_attrs["node_type"] = @kgf_features.node_type_document
    doc_attrs["content_type"] = content_type
    doc_attrs["node_kind"] = kind_str
    if lang.length() > 0 {
      doc_attrs["language"] = lang
    }
    doc_attrs["parent"] = file_id
    out.push({
      id,
      text: section.title + " " + section.content,
      title: if idx == 0 {
        file_title
      } else {
        section.title
      },
      source: path,
      line: 0,
      kind: kind_str,
      attrs: doc_attrs,
    })
  }
}

///|
fn push_whole_file_document(
  path : String,
  content : String,
  lang : String,
  content_type : String,
  out : Array[@search_engine.SearchDocument],
) -> Unit {
  let attrs : Map[String, String] = {}
  attrs["node_type"] = @kgf_features.node_type_document
  attrs["node_kind"] = "file"
  attrs["content_type"] = content_type
  if lang.length() > 0 {
    attrs["language"] = lang
  }
  let title = @config.basename(path)
  out.push({
    id: path,
    text: title + " " + content,
    title,
    source: path,
    line: 1,
    kind: "file",
    attrs,
  })
}

///|
fn extract_code_file_documents(
  code_files : Array[(String, String)],
  registry : @kgf_registry.KGFRegistry?,
  out : Array[@search_engine.SearchDocument],
) -> Unit {
  for file in code_files {
    let (path, content) = file
    let lang = match registry {
      Some(reg) =>
        match reg.detect_from_path(path) {
          Some(value) => value
          None => ""
        }
      None => ""
    }
    let attrs : Map[String, String] = {}
    attrs["node_type"] = @kgf_features.node_type_code
    attrs["node_kind"] = "file"
    if lang.length() > 0 {
      attrs["language"] = lang
    }
    out.push({
      id: path,
      text: @config.basename(path) + " " + content,
      title: @config.basename(path),
      source: path,
      line: 1,
      kind: "file",
      attrs,
    })
  }
}
