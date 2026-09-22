///|
/// Maximum display length of a concept's frontmatter `description` — a
/// single-sentence preview per the OKF spec, truncated for search/index UIs.
const DESCRIPTION_MAX_LENGTH : Int = 160

///|
/// Assembly of OKF package concepts from analyzed knowledge.
///
/// Everything here is data-driven: package membership comes from discovered
/// package paths, symbol filtering from the KGF `document_symbol_kinds`
/// feature, external prefixes from the KGF resolver (`bare_prefix`), and
/// internal/external classification from the graph plus suffix matching
/// against the analyzed package set. Nothing language-specific is hardcoded.

///|
/// Convert discovered packages plus the analyzed graph into OKF concepts.
fn assemble_concepts(
  packages : Array[@readme.PackageInfo],
  graph : @graph.CodeGraph,
  registry : @registry.KGFRegistry,
  specs : Map[String, @kgf_types.KGFSpec],
  contents : Map[String, String],
) -> Array[@okf_bundle.OkfPackageConcept] {
  // (normalized path, raw path) pairs for internal-target resolution.
  let package_paths : Array[(String, String)] = []
  for pkg in packages {
    package_paths.push((@okf_bundle.normalize_package_path(pkg.path), pkg.path))
  }
  let result : Array[@okf_bundle.OkfPackageConcept] = []
  for pkg in packages {
    let overview = package_overview(pkg, graph, registry, contents)
    let summary_line = first_prose_line(overview, DESCRIPTION_MAX_LENGTH)
    let description = if summary_line.length() > 0 {
      summary_line
    } else {
      "Package " +
      pkg.name +
      " containing " +
      pkg.files.length().to_string() +
      " source file(s)."
    }
    result.push({
      path: pkg.path,
      name: pkg.name,
      overview,
      description,
      languages: package_languages(pkg, registry),
      files: pkg.files.copy(),
      declarations: package_declarations(pkg, graph, specs),
      depends_on: package_dependencies(pkg, graph, registry, package_paths),
    })
  }
  result
}

///|
/// Package overview prose. Curated knowledge wins: the summary of a
/// document-type file in the package (e.g. its README) is preferred, then
/// the prose prefix of module_doc notes from the graph (their generated
/// API listings are dropped — the Schema section already covers symbols).
fn package_overview(
  pkg : @readme.PackageInfo,
  graph : @graph.CodeGraph,
  registry : @registry.KGFRegistry,
  contents : Map[String, String],
) -> String {
  for file in pkg.files {
    if @kgf_features.is_document_file(file, Some(registry)) == Some(true) {
      match contents.get(file) {
        Some(content) => {
          // Keep only the leading prose of the document summary; generated
          // API listings carry no knowledge the Schema section lacks.
          let summary = prose_prefix(@readme.extract_summary(content))
          if summary.length() > 0 {
            return summary
          }
        }
        None => ()
      }
    }
  }
  let buf = StringBuilder()
  let seen : Map[String, Bool] = Map([])
  let module_ids : Array[String] = [pkg.path]
  for file in pkg.files {
    module_ids.push(file)
  }
  for module_id in module_ids {
    match graph.get_module_doc(module_id) {
      Some(doc) => {
        let prose = prose_prefix(doc)
        if prose.length() > 0 && !seen.contains(prose) {
          seen.set(prose, true)
          buf.write_string(prose)
          buf.write_string("\n\n")
        }
      }
      None => ()
    }
  }
  @common.trim_ascii_spaces(buf.to_string())
}

///|
/// Lines of a text before its first markdown heading, trimmed.
fn prose_prefix(text : String) -> String {
  let kept : Array[String] = []
  for line in @common.split_lines(text) {
    if @common.trim_ascii_spaces(line).has_prefix("#") {
      break
    }
    kept.push(line)
  }
  let buf = StringBuilder()
  for i, line in kept {
    if i > 0 {
      buf.write_string("\n")
    }
    buf.write_string(line)
  }
  @common.trim_ascii_spaces(buf.to_string())
}

///|
/// KGF language names present in the package, deduplicated and sorted.
fn package_languages(
  pkg : @readme.PackageInfo,
  registry : @registry.KGFRegistry,
) -> Array[String] {
  let result : Array[String] = []
  for file in pkg.files {
    match registry.detect_from_path(file) {
      Some(lang) => if !result.contains(lang) { result.push(lang) }
      None => ()
    }
  }
  result.sort()
  result
}

///|
/// Public declarations for the package's Schema section, filtered through
/// the KGF `document_symbol_kinds` feature.
fn package_declarations(
  pkg : @readme.PackageInfo,
  graph : @graph.CodeGraph,
  specs : Map[String, @kgf_types.KGFSpec],
) -> Array[@okf_bundle.OkfDeclaration] {
  let kind_filter = @kgf_features.document_symbol_kind_filter(pkg.files, specs)
  let result : Array[@okf_bundle.OkfDeclaration] = []
  let seen : Map[String, Bool] = Map([])
  for entry in graph.get_symbols() {
    let sym = entry.1
    if @common.parent_dir(sym.module_id) != pkg.path {
      continue
    }
    match kind_filter {
      Some(filter) =>
        if !filter.contains(@kgf_features.to_lower_str(sym.kind)) {
          continue
        }
      None => ()
    }
    let key = sym.kind + ":" + sym.name
    if seen.contains(key) {
      continue
    }
    seen.set(key, true)
    let doc = match sym.doc {
      Some(d) => first_prose_line(d, DESCRIPTION_MAX_LENGTH)
      None => ""
    }
    result.push({ name: sym.name, kind: sym.kind, doc, })
  }
  result
}

///|
/// Dependencies of the package derived from ModuleDependsOn edges.
/// Targets are resolved in order: a graph module with a real file (internal),
/// a resolver-prefixed import that suffix-matches an analyzed package
/// (internal), a resolver-prefixed import (external), or a bare target that
/// suffix-matches an analyzed package (internal). Anything else is an
/// unresolvable artifact and is skipped.
fn package_dependencies(
  pkg : @readme.PackageInfo,
  graph : @graph.CodeGraph,
  registry : @registry.KGFRegistry,
  package_paths : Array[(String, String)],
) -> Array[@okf_bundle.OkfDepRef] {
  let prefixes = registry.get_external_prefixes()
  let collected : Map[String, @okf_bundle.OkfDepRef] = Map([])
  let own_norm = @okf_bundle.normalize_package_path(pkg.path)
  for edge in graph.get_edges() {
    if !(edge.kind is @graph.ModuleDependsOn) {
      continue
    }
    if @common.parent_dir(edge.from) != pkg.path {
      continue
    }
    // Only a local alias is worth annotating; the raw import path would
    // just duplicate the link target.
    let via = edge.attrs.get("alias")
    let mut internal_target : String? = None
    let mut external_target : String? = None
    match graph.get_module(edge.to) {
      Some(target_module) =>
        if target_module.file is Some(_) {
          let dir = @common.parent_dir(edge.to)
          match exact_package_match(dir, package_paths) {
            Some(raw) => internal_target = Some(raw)
            // Analyzed file outside the discovered package set (e.g. dropped
            // by --include/--exclude): out-of-bundle knowledge, so surface it
            // as an external dependency concept — same as prefix-resolved
            // imports that do not match an analyzed package.
            None => external_target = Some(dir)
          }
        }
      None => ()
    }
    if internal_target is None {
      match strip_external_prefix(edge.to, prefixes) {
        Some(stripped) =>
          match resolve_internal_target(stripped, package_paths) {
            Some(raw) => internal_target = Some(raw)
            None => external_target = Some(stripped)
          }
        None =>
          match resolve_internal_target(edge.to, package_paths) {
            Some(raw) => internal_target = Some(raw)
            None => ()
          }
      }
    }
    match internal_target {
      Some(raw) => {
        let norm = @okf_bundle.normalize_package_path(raw)
        if norm == own_norm {
          continue
        }
        upsert_dep(collected, "i:" + norm, { target: raw, internal: true, via, })
      }
      None =>
        match external_target {
          Some(ext) =>
            upsert_dep(collected, "e:" + ext, {
              target: ext,
              internal: false,
              via,
            })
          None => ()
        }
    }
  }
  let result : Array[@okf_bundle.OkfDepRef] = []
  for entry in collected {
    result.push(entry.1)
  }
  result
}

///|
/// Record a dependency, upgrading an alias-less earlier edge with the alias
/// from a later duplicate (manifest edges precede source-alias edges).
fn upsert_dep(
  collected : Map[String, @okf_bundle.OkfDepRef],
  key : String,
  dep : @okf_bundle.OkfDepRef,
) -> Unit {
  match collected.get(key) {
    Some(existing) =>
      if existing.via is None && dep.via is Some(_) {
        collected.set(key, dep)
      }
    None => collected.set(key, dep)
  }
}

///|
/// Strip the first matching KGF resolver prefix (e.g. a `bare_prefix`)
/// from a dependency target. Returns None when no prefix matches.
fn strip_external_prefix(target : String, prefixes : Array[String]) -> String? {
  for prefix in prefixes {
    if prefix.length() > 0 && target.has_prefix(prefix) {
      let rest = @common.substring(target, prefix.length(), target.length())
      // Tolerate prefixes declared without their separator.
      if rest.has_prefix(":") {
        return Some(@common.substring(rest, 1, rest.length()))
      }
      return Some(rest)
    }
  }
  None
}

///|
/// Exact membership check of a directory path in the analyzed package set.
/// Returns the package's raw path when its normalized form matches.
fn exact_package_match(
  dir : String,
  package_paths : Array[(String, String)],
) -> String? {
  let norm = @okf_bundle.normalize_package_path(dir)
  for entry in package_paths {
    if entry.0 == norm {
      return Some(entry.1)
    }
  }
  None
}

///|
/// Resolve an import path to an analyzed package by longest suffix match.
/// Example: `acme/tool/src/kgf/parser` matches the analyzed package
/// `src/kgf/parser`. Returns the package's raw path.
fn resolve_internal_target(
  import_path : String,
  package_paths : Array[(String, String)],
) -> String? {
  let mut best : String? = None
  let mut best_len = -1
  for entry in package_paths {
    let (norm, raw) = entry
    if norm.length() == 0 {
      continue
    }
    if import_path == norm || import_path.has_suffix("/" + norm) {
      if norm.length() > best_len {
        best = Some(raw)
        best_len = norm.length()
      }
    }
  }
  best
}

///|
/// First prose line of a text, truncated for display. Lines that read as
/// markdown structure (headings, list items, tables, quotes, code) are not
/// prose and are skipped.
fn first_prose_line(text : String, max_length : Int) -> String {
  for line in @common.split_lines(text) {
    let trimmed = @common.trim_ascii_spaces(line)
    if trimmed.length() == 0 {
      continue
    }
    if trimmed.has_prefix("#") ||
      trimmed.has_prefix("-") ||
      trimmed.has_prefix("*") ||
      trimmed.has_prefix("|") ||
      trimmed.has_prefix(">") ||
      trimmed.has_prefix("`") {
      continue
    }
    return @common.truncate(trimmed, max_length)
  }
  ""
}
