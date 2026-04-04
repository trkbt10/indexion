///|
/// Get document symbol kinds from KGF spec, falling back to "all kinds" if not specified.
fn document_symbol_kinds(spec : @kgf_types.KGFSpec) -> Map[String, Bool]? {
  match spec.get_feature("document_symbol_kinds") {
    Some(kinds) => {
      let m : Map[String, Bool] = {}
      for kind in kinds {
        m.set(@kgf_features.to_lower_str(kind), true)
      }
      Some(m)
    }
    None => None // No filter — include all kinds
  }
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
/// Code unit extraction using full KGF pipeline (tokenize → parse → eval_semantics → declares edges).
/// All public declarations are identified via KGF semantics — no hardcoded keyword patterns.
fn build_code_units_fast(
  discovered_paths : Array[String],
  registry : @registry.KGFRegistry,
) -> Array[CodeUnit] {
  let units : Array[CodeUnit] = []
  for path in discovered_paths {
    let lang = match registry.detect_from_path(path) {
      Some(l) => l
      None => continue
    }
    let spec = match registry.get_spec(lang) {
      Some(s) => s
      None => continue
    }
    let content = @fs.read_file_to_string(path) catch { _ => continue }
    // Full KGF pipeline: tokenize → parse → eval_semantics → declares edges
    let (pub_decls, doc_map) = @kgf_features.extract_pub_declarations_and_doc_map(
      content,
      path,
      Some(registry),
    )
    // Optional kind filter from KGF spec's document_symbol_kinds feature
    let kind_filter = document_symbol_kinds(spec)
    let module_id = path
    for decl in pub_decls {
      let kind = decl.kind
      // Apply kind filter if the spec defines document_symbol_kinds
      match kind_filter {
        Some(filter) => if !filter.contains(kind) { continue }
        None => ()
      }
      let symbol_id = path + "::" + decl.name
      let inline_doc = doc_map.get(decl.line)
      let code_hash = make_hash([
        symbol_id,
        decl.name,
        kind,
        "",
        module_id,
        inline_doc.unwrap_or(""),
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
  }
  units.sort_by(fn(a, b) { a.symbol_id.compare(b.symbol_id) })
  units
}
