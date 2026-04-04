///|
/// Vector similarity search — find code similar to a natural language query.
/// Delegates to the shared `@search.inline_search` engine.

///|
/// Extract function-level SearchDocuments from source files.
pub fn extract_code_documents(
  files : Array[(String, String)],
  registry : @kgf_registry.KGFRegistry?,
) -> Array[@search.SearchDocument] {
  let docs : Array[@search.SearchDocument] = []
  for file in files {
    let (path, content) = file
    let tokens = match @kgf_features.tokenize_source(content, path, registry) {
      Some(t) => t
      None => continue
    }
    let spec = match registry {
      Some(r) =>
        match r.detect_from_path(path) {
          Some(lang) => r.get_spec(lang)
          None => None
        }
      None => None
    }
    let s = match spec {
      Some(s) => s
      None => continue
    }
    let functions = @kgf_features.extract_functions(tokens, path, spec=s)
    let token_lines = build_token_lines(tokens)
    let lines = @common.split_lines(content)
    for func in functions {
      let start_line = if func.get_start() < token_lines.length() {
        token_lines[func.get_start()]
      } else {
        1
      }
      let end_line = if func.get_end() > 0 &&
        func.get_end() - 1 < token_lines.length() {
        token_lines[func.get_end() - 1]
      } else {
        lines.length()
      }
      let buf = StringBuilder::new()
      buf.write_string(func.get_name())
      buf.write_string(" ")
      let start_idx = start_line - 1
      let end_idx = if end_line > lines.length() {
        lines.length()
      } else {
        end_line
      }
      for i = start_idx; i < end_idx; i = i + 1 {
        if i < lines.length() {
          buf.write_string(lines[i])
          buf.write_string(" ")
        }
      }
      let lang = match registry {
        Some(reg) =>
          match reg.detect_from_path(path) {
            Some(l) => l
            None => ""
          }
        None => ""
      }
      let module_path = @common.parent_dir(path)
      let doc_attrs : Map[String, String] = {}
      doc_attrs["node_type"] = @kgf_features.node_type_code
      doc_attrs["node_kind"] = "fn"
      if lang.length() > 0 {
        doc_attrs["language"] = lang
      }
      if module_path.length() > 0 {
        doc_attrs["module"] = module_path
      }
      docs.push({
        id: path + ":" + start_line.to_string(),
        text: buf.to_string(),
        title: func.get_name(),
        source: path,
        line: start_line,
        kind: "fn",
        attrs: doc_attrs,
      })
    }
  }
  docs
}

///|
/// Run vector similarity search across the codebase.
pub fn run_similar_search(
  paths : Array[String],
  query_text : String,
  top_k : Int,
  config : GrepConfig,
) -> Unit {
  let (registry, files) = match load_registry_and_files(paths, config) {
    Some(r) => r
    None => return
  }
  if files.is_empty() {
    println("No files found")
    return
  }
  let docs = extract_code_documents(files, registry)
  if docs.is_empty() {
    println("No functions found")
    return
  }
  let hits = @search.inline_search(docs, query_text, top_k)
  for hit in hits {
    let doc = hit.document
    let score_str = @common.format_percent(hit.score)
    if config.files_only {
      println(doc.source)
    } else {
      println(
        doc.source +
        ":" +
        doc.line.to_string() +
        ": fn " +
        doc.title +
        "  (" +
        score_str +
        " similar)",
      )
    }
  }
  println("")
  println(
    hits.length().to_string() +
    " results from " +
    docs.length().to_string() +
    " functions",
  )
}
