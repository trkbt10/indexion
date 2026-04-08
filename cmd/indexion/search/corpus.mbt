///|
/// # Corpus Construction
///
/// Discovers files, classifies them by KGF spec characteristics,
/// and builds SearchDocuments. No hardcoded file extensions or content types.

///|
/// Build a search corpus from the given paths.
/// Classifies files using KGF spec features: specs with content_type: document
/// are indexed by section splitting, others by function extraction.
fn build_corpus(
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
    // 5. Build code documents via CodeGraph (includes edge info)
    if code_files.length() > 0 {
      if has_directory_input(file_paths) {
        let graph_target = graph_target_dir(file_paths)
        extract_code_documents_with_graph(
          code_files,
          registry,
          config.specs_dir,
          graph_target,
          documents,
        )
      } else {
        extract_code_file_documents(code_files, registry, documents)
      }
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
fn has_directory_input(paths : Array[String]) -> Bool {
  for path in paths {
    if path_is_dir(path) {
      return true
    }
  }
  false
}

///|
fn path_is_dir(path : String) -> Bool {
  @fs.is_dir(path) catch {
    _ => false
  }
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
    let page_path = wiki_dir + "/" + page_file
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
/// Build code documents via CodeGraph when possible.
/// Falls back to direct function extraction if graph construction fails.
/// When CodeGraph is available, includes edge information (callers/callees count).
fn extract_code_documents_with_graph(
  code_files : Array[(String, String)],
  registry : @kgf_registry.KGFRegistry?,
  specs_dir : String,
  target_dir : String,
  out : Array[@search_engine.SearchDocument],
) -> Unit {
  let build_result = @digest_cli.build_graph_from_source(target_dir, specs_dir)
  match build_result {
    Some(r) => extract_code_from_graph(r.graph, code_files, registry, out)
    None => {
      // Fallback: use direct function extraction (no graph edges)
      let code_docs = @grep.extract_code_documents(code_files, registry)
      for doc in code_docs {
        out.push(doc)
      }
    }
  }
}

///|
/// Extract code documents from CodeGraph with edge information.
fn extract_code_from_graph(
  graph : @graph.CodeGraph,
  code_files : Array[(String, String)],
  registry : @kgf_registry.KGFRegistry?,
  out : Array[@search_engine.SearchDocument],
) -> Unit {
  // Build set of target file paths for filtering
  let file_set : Map[String, Bool] = {}
  for file in code_files {
    file_set[file.0] = true
  }
  // Build module_id → file path mapping
  let module_files : Map[String, String] = {}
  for mod_entry in graph.get_modules() {
    match mod_entry.1.file {
      Some(f) => module_files[mod_entry.0] = f
      None => ()
    }
  }
  for entry in graph.get_symbols() {
    let symbol = entry.1
    let module_file = match module_files.get(symbol.module_id) {
      Some(f) => f
      None => continue
    }
    // Only include symbols from target files
    if !file_set.contains(module_file) {
      continue
    }
    let lang = match registry {
      Some(reg) =>
        match reg.detect_from_path(module_file) {
          Some(l) => l
          None => ""
        }
      None => ""
    }
    let buf = StringBuilder::new()
    buf.write_string(symbol.name)
    buf.write_string(" ")
    buf.write_string(symbol.kind)
    buf.write_string(" ")
    buf.write_string(symbol.ns)
    buf.write_string(" ")
    buf.write_string(@config.basename(module_file))
    buf.write_string(" ")
    buf.write_string(symbol.module_id)
    let callers = graph.get_callers(entry.0)
    let callees = graph.get_callees(entry.0)
    let doc_attrs : Map[String, String] = {}
    doc_attrs["node_type"] = @kgf_features.node_type_code
    doc_attrs["node_kind"] = symbol.kind
    if lang.length() > 0 {
      doc_attrs["language"] = lang
    }
    doc_attrs["module"] = symbol.module_id
    doc_attrs["callers"] = callers.length().to_string()
    doc_attrs["callees"] = callees.length().to_string()
    match symbol.doc {
      Some(doc) => {
        doc_attrs["doc"] = doc
        buf.write_string(" ")
        buf.write_string(doc)
      }
      None => ()
    }
    out.push({
      id: module_file + ":" + symbol.name,
      text: buf.to_string(),
      title: symbol.name,
      source: module_file,
      line: 0,
      kind: symbol.kind,
      attrs: doc_attrs,
    })
  }
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
