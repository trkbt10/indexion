///|
fn default_document_symbol_kinds() -> Map[String, Bool] {
  let kinds : Map[String, Bool] = {}
  for
    kind in [
      "function", "type", "struct", "enum", "trait", "class", "interface", "module",
    ] {
    kinds.set(kind, true)
  }
  kinds
}

///|
fn document_symbol_kinds_for_path(
  path : String,
  registry : @registry.KGFRegistry,
) -> Map[String, Bool] {
  let fallback = default_document_symbol_kinds()
  match registry.detect_from_path(path) {
    Some(lang) =>
      match registry.get_spec(lang) {
        Some(spec) =>
          match spec.get_feature("document_symbol_kinds") {
            Some(values) => {
              let configured : Map[String, Bool] = {}
              for value in values {
                let normalized = lower_string(@common.trim_ascii_spaces(value))
                if normalized.length() > 0 {
                  configured.set(normalized, true)
                }
              }
              if configured.is_empty() {
                fallback
              } else {
                configured
              }
            }
            None => fallback
          }
        None => fallback
      }
    None => fallback
  }
}

///|
fn should_include_symbol(
  kind : String,
  module_path : String,
  registry : @registry.KGFRegistry,
) -> Bool {
  document_symbol_kinds_for_path(module_path, registry).contains(
    lower_string(kind),
  )
}

///|
fn discovery_roots(target_dir : String) -> Array[String] {
  if target_dir != "." {
    return [target_dir]
  }
  let entries = @fs.read_dir(target_dir) catch { _ => return [target_dir] }
  let roots : Array[String] = []
  for entry in entries {
    if entry != "." && entry != ".." {
      roots.push(entry)
    }
  }
  if roots.length() == 0 {
    [target_dir]
  } else {
    roots
  }
}

///|
fn build_code_graph(
  target_dir : String,
  specs_dir : String,
) -> (@registry.KGFRegistry, Array[String], @graph.CodeGraph) {
  let registry = @registry.KGFRegistry::load_from_dir(specs_dir)
  let kgf_ignore = registry.collect_ignore_patterns()
  let discover_opts = @pipeline.DiscoverOptions::new(
    kgf_ignore~,
    root_dir=target_dir,
  )
  let discovered_paths = @pipeline.discover_files(
    discovery_roots(target_dir),
    discover_opts,
  )
  let files = @pipeline.collect_supported_files(discovered_paths, registry)
  let specs = registry.to_specs_map()
  let config = @doc_build.DocConfig::new(files, specs, root_path=target_dir)
  let (_output, graph) = @doc_build.build_with_graph(config)
  (registry, discovered_paths, graph)
}

///|
/// Fast code unit extraction using KGF lexer only (no PEG parse).
/// ~10x faster than build_code_graph + extract_code_units for large projects.
fn build_code_units_fast(
  discovered_paths : Array[String],
  registry : @registry.KGFRegistry,
) -> Array[CodeUnit] {
  let units : Array[CodeUnit] = []
  let symbol_kinds = default_document_symbol_kinds()
  for path in discovered_paths {
    // Only process files the registry recognizes
    let lang = match registry.detect_from_path(path) {
      Some(l) => l
      None => continue
    }
    let spec = match registry.get_spec(lang) {
      Some(s) => s
      None => continue
    }
    let content = @fs.read_file_to_string(path) catch { _ => continue }
    // Use KGF lexer to extract pub declarations (no PEG needed)
    let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
    let tokens = lexer.tokenize(content)
    let functions = @kgf_features.extract_functions(tokens, path)
    let pub_decls = @kgf_features.extract_pub_declarations(
      content, path, Some(registry),
    )
    // Scan for doc comments and associate with declarations
    let lines = @common.split_lines(content)
    let line_docs : Map[Int, String] = {}
    let mut doc_buf = StringBuilder::new()
    let mut in_doc = false
    for i, line in lines {
      let trimmed = @common.trim_ascii_spaces(line)
      if trimmed.has_prefix("///|") {
        in_doc = true
        doc_buf = StringBuilder::new()
      } else if in_doc && trimmed.has_prefix("///") {
        let doc_text = if trimmed.length() > 4 {
          @common.substring(trimmed, 4, trimmed.length())
        } else {
          ""
        }
        if doc_buf.to_string().length() > 0 {
          doc_buf.write_string("\n")
        }
        doc_buf.write_string(doc_text)
      } else if in_doc {
        // End of doc block — associate with this line
        let doc = doc_buf.to_string()
        if doc.length() > 0 {
          line_docs.set(i + 1, doc)
        }
        in_doc = false
      }
    }
    // Module ID from path (dirname-based)
    let module_id = path
    // Build code units from pub declarations
    for decl in pub_decls {
      let kind = decl.kind
      if not(symbol_kinds.contains(kind)) {
        continue
      }
      let symbol_id = path + "::" + decl.name
      let inline_doc = line_docs.get(decl.line)
      let code_hash = make_hash([
        symbol_id,
        decl.name,
        kind,
        "",
        module_id,
        inline_doc.or(""),
      ])
      units.push({
        symbol_id,
        name: decl.name,
        kind,
        ns: "",
        module_id,
        module_path: path,
        inline_doc,
        code_hash,
      })
    }
    // Also include functions (which may not have pub prefix in some languages)
    for func in functions {
      let symbol_id = path + "::" + func.get_name()
      // Skip if already added from pub_decls
      let mut exists = false
      for u in units {
        if u.symbol_id == symbol_id {
          exists = true
          break
        }
      }
      if exists {
        continue
      }
      // Only include if it matches document_symbol_kinds
      if not(symbol_kinds.contains("function")) {
        continue
      }
      let code_hash = make_hash([
        symbol_id, func.get_name(), "function", "", module_id, "",
      ])
      units.push({
        symbol_id,
        name: func.get_name(),
        kind: "function",
        ns: "",
        module_id,
        module_path: path,
        inline_doc: None,
        code_hash,
      })
    }
  }
  units.sort_by(fn(a, b) { a.symbol_id.compare(b.symbol_id) })
  units
}

///|
fn extract_code_units(
  graph : @graph.CodeGraph,
  registry : @registry.KGFRegistry,
) -> Array[CodeUnit] {
  let units : Array[CodeUnit] = []
  for entry in graph.get_symbols() {
    let symbol = entry.1
    let module_path = match graph.get_module(symbol.module_id) {
      Some(module_node) =>
        match module_node.file {
          Some(file) => file
          None => symbol.module_id
        }
      None => symbol.module_id
    }
    if not(should_include_symbol(symbol.kind, module_path, registry)) {
      continue
    }
    let code_hash = make_hash([
      symbol.id,
      symbol.name,
      symbol.kind,
      symbol.ns,
      module_path,
      match symbol.doc {
        Some(doc) => doc
        None => ""
      },
    ])
    units.push({
      symbol_id: symbol.id,
      name: symbol.name,
      kind: symbol.kind,
      ns: symbol.ns,
      module_id: symbol.module_id,
      module_path,
      inline_doc: symbol.doc,
      code_hash,
    })
  }
  units.sort_by(fn(a, b) { a.symbol_id.compare(b.symbol_id) })
  units
}
