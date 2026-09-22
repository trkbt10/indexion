///|
priv struct LocalEntitySummary {
  kind : String
  path : String
  origin_hint : String
  name : String
  actual_summary : String
  declaration_symbols : Int
  behavior_symbols : Int
}

///|
priv struct LocalEntityProfile {
  declaration_symbols : Int
  behavior_symbols : Int
}

///|
priv struct PathNameModel {
  basename_counts : Map[String, Int]
}

///|
pub fn audit_code_identity(config : IdentityAuditConfig) -> IdentityAuditReport {
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir=config.specs_dir,
    target_dirs=config.paths,
  )
  let discovered = discover_supported_files(config, registry)
  if discovered.is_empty() {
    return empty_audit_report(config.threshold, ["no supported files found"])
  }
  let model = build_path_name_model(discovered)
  let files : Array[(String, String)] = []
  for file in discovered {
    files.push((file.path, file.content))
  }
  let graph = build_graph(files, registry)
  let file_summaries = build_file_summaries(discovered, graph, registry, model)
  let entities : Array[LocalEntitySummary] = []
  for file in file_summaries {
    entities.push(file)
  }
  if config.include_folders {
    for folder in build_folder_summaries(file_summaries, model) {
      entities.push(folder)
    }
  }
  if config.include_symbols {
    for symbol in build_symbol_summaries(graph) {
      entities.push(symbol)
    }
  }
  let candidates : Array[IdentityAuditCandidate] = []
  for entity in entities {
    let candidate = score_audit_entity(entity, registry)
    if candidate.divergence >= config.threshold && needs_review(candidate) {
      candidates.push(candidate)
    }
  }
  candidates.sort_by(fn(a, b) {
    let c = assessment_priority(a.assessment).compare(
      assessment_priority(b.assessment),
    )
    if c != 0 {
      c
    } else {
      let d = b.divergence.compare(a.divergence)
      if d != 0 {
        d
      } else {
        a.path.compare(b.path)
      }
    }
  })
  let limited = limit_candidates(candidates, config.limit)
  {
    version: "identity-audit-v1",
    summary: {
      scanned: entities.length(),
      candidates: candidates.length(),
      threshold: config.threshold,
      max_divergence: max_divergence(candidates),
    },
    candidates: limited,
    skipped: [],
  }
}

///|
fn empty_audit_report(
  threshold : Double,
  skipped : Array[String],
) -> IdentityAuditReport {
  {
    version: "identity-audit-v1",
    summary: { scanned: 0, candidates: 0, threshold, max_divergence: 0.0, },
    candidates: [],
    skipped,
  }
}

///|
fn discover_supported_files(
  config : IdentityAuditConfig,
  registry : @kgf_registry.KGFRegistry,
) -> Array[@pipeline.SupportedFile] {
  let kgf_ignore = registry.collect_ignore_patterns()
  let discover_opts = @pipeline.DiscoverOptions::new(
    root_dir=@pipeline.root_dir_from_paths(config.paths),
    recursive=true,
    kgf_ignore~,
  )
  @pipeline.collect_supported_file_info(config.paths, discover_opts, registry)
}

///|
fn build_graph(
  files : Array[(String, String)],
  registry : @kgf_registry.KGFRegistry,
) -> @graph.CodeGraph {
  let doc_config = @build.DocConfig::new(
    files,
    registry.to_specs_map(),
    options=@render.RenderOptions::new(format=@render.OutputFormat::json()),
  )
  let (_, graph) = @build.build_with_graph(doc_config)
  graph
}

///|
fn build_path_name_model(
  files : Array[@pipeline.SupportedFile],
) -> PathNameModel {
  let basename_counts : Map[String, Int] = Map([])
  for file in files {
    let base = @config_paths.basename(file.path)
    basename_counts[base] = basename_counts.get(base).unwrap_or(0) + 1
  }
  { basename_counts, }
}

///|
fn build_file_summaries(
  files : Array[@pipeline.SupportedFile],
  graph : @graph.CodeGraph,
  registry : @kgf_registry.KGFRegistry,
  model : PathNameModel,
) -> Array[LocalEntitySummary] {
  let by_module : Map[String, Array[String]] = Map([])
  let profiles : Map[String, LocalEntityProfile] = Map([])
  for entry in graph.get_symbols() {
    let sym = entry.1
    let text = symbol_summary_text(sym.name, sym.doc)
    match by_module.get(sym.module_id) {
      Some(arr) => arr.push(text)
      None => by_module.set(sym.module_id, [text])
    }
    profiles.set(
      sym.module_id,
      profile_with_symbol(profiles.get(sym.module_id), sym.kind),
    )
  }
  let result : Array[LocalEntitySummary] = []
  for file in files {
    let summary = StringBuilder()
    match by_module.get(file.path) {
      Some(symbols) =>
        for symbol in symbols {
          summary.write_string(symbol)
          summary.write_string("\n")
        }
      None => ()
    }
    let profile = profiles.get(file.path).unwrap_or(empty_entity_profile())
    for note in graph.get_notes("module_doc", file.path) {
      summary.write_string(note.content)
      summary.write_string("\n")
    }
    append_feature_values(summary, file.content, file.path, registry)
    result.push({
      kind: "file",
      path: file.path,
      origin_hint: file.path,
      name: scoped_path_name(file.path, model),
      actual_summary: summary.to_string(),
      declaration_symbols: profile.declaration_symbols,
      behavior_symbols: profile.behavior_symbols,
    })
  }
  result
}

///|
fn build_folder_summaries(
  files : Array[LocalEntitySummary],
  model : PathNameModel,
) -> Array[LocalEntitySummary] {
  let by_dir : Map[String, Array[LocalEntitySummary]] = Map([])
  for file in files {
    let dir = @config_paths.dirname(file.path)
    if dir.length() == 0 || dir == "." {
      continue
    }
    match by_dir.get(dir) {
      Some(arr) => arr.push(file)
      None => by_dir.set(dir, [file])
    }
  }
  let result : Array[LocalEntitySummary] = []
  for entry in by_dir {
    let dir = entry.0
    let children = entry.1
    if children.length() < 2 {
      continue
    }
    let summary = StringBuilder()
    let limit = if children.length() < 8 { children.length() } else { 8 }
    for i = 0; i < limit; i = i + 1 {
      summary.write_string(children[i].name)
      summary.write_string("\n")
      summary.write_string(children[i].actual_summary)
      summary.write_string("\n")
    }
    result.push({
      kind: "folder",
      path: dir,
      origin_hint: children[0].origin_hint,
      name: scoped_path_name(dir, model),
      actual_summary: summary.to_string(),
      declaration_symbols: count_declaration_symbols(children),
      behavior_symbols: count_behavior_symbols(children),
    })
  }
  result
}

///|
fn build_symbol_summaries(
  graph : @graph.CodeGraph,
) -> Array[LocalEntitySummary] {
  let result : Array[LocalEntitySummary] = []
  for entry in graph.get_symbols() {
    let sym = entry.1
    if !is_identity_symbol_kind(sym.kind) {
      continue
    }
    let path = match graph.get_module(sym.module_id) {
      Some(mod_node) =>
        match mod_node.file {
          Some(file) => file
          None => sym.module_id
        }
      None => sym.module_id
    }
    result.push({
      kind: "symbol",
      path,
      origin_hint: path,
      name: sym.name,
      actual_summary: symbol_summary_text(sym.name, sym.doc),
      declaration_symbols: if is_declaration_symbol_kind(sym.kind) {
        1
      } else {
        0
      },
      behavior_symbols: if is_behavior_symbol_kind(sym.kind) {
        1
      } else {
        0
      },
    })
  }
  result
}

///|
fn is_identity_symbol_kind(kind : String) -> Bool {
  is_behavior_symbol_kind(kind) || is_declaration_symbol_kind(kind)
}

///|
fn is_behavior_symbol_kind(kind : String) -> Bool {
  kind == "Function"
}

///|
fn is_declaration_symbol_kind(kind : String) -> Bool {
  kind == "Class" ||
  kind == "Interface" ||
  kind == "Struct" ||
  kind == "Enum" ||
  kind == "Type"
}

///|
fn empty_entity_profile() -> LocalEntityProfile {
  { declaration_symbols: 0, behavior_symbols: 0, }
}

///|
fn profile_with_symbol(
  current : LocalEntityProfile?,
  kind : String,
) -> LocalEntityProfile {
  let profile = current.unwrap_or(empty_entity_profile())
  let declaration_symbols = if is_declaration_symbol_kind(kind) { 1 } else { 0 }
  let behavior_symbols = if is_behavior_symbol_kind(kind) { 1 } else { 0 }
  {
    declaration_symbols: profile.declaration_symbols + declaration_symbols,
    behavior_symbols: profile.behavior_symbols + behavior_symbols,
  }
}

///|
fn count_declaration_symbols(children : Array[LocalEntitySummary]) -> Int {
  let mut total = 0
  for child in children {
    total = total + child.declaration_symbols
  }
  total
}

///|
fn count_behavior_symbols(children : Array[LocalEntitySummary]) -> Int {
  let mut total = 0
  for child in children {
    total = total + child.behavior_symbols
  }
  total
}

///|
fn score_audit_entity(
  entity : LocalEntitySummary,
  registry : @kgf_registry.KGFRegistry,
) -> IdentityAuditCandidate {
  let expected = expected_summary(entity)
  let similarity = bm25_similarity(expected, entity.actual_summary)
  let divergence = 1.0 - similarity
  let name_report = score_name_divergence(
    NamedEntity::new(
      name=Name::single(entity.name),
      content=entity.actual_summary,
      origin=entity.origin_hint,
    ),
    registry,
  )
  let action = effective_identity_action(entity, name_report)
  {
    kind: entity.kind,
    path: entity.path,
    name: entity.name,
    expected_summary: expected,
    actual_summary: entity.actual_summary,
    similarity,
    divergence,
    identity_action: action.label(),
    assessment: assessment_for(action),
    prominent_unused: name_report.get_prominent_unused(),
    recommendation: recommendation_for(entity, action, divergence),
  }
}

///|
fn needs_review(candidate : IdentityAuditCandidate) -> Bool {
  candidate.identity_action != Keep.label()
}

///|
fn expected_summary(entity : LocalEntitySummary) -> String {
  let summary = StringBuilder()
  summary.write_string(entity.kind)
  summary.write_string(" ")
  summary.write_string(entity.name)
  summary.write_string("\npath ")
  summary.write_string(entity.path)
  summary.write_string("\nexpected scope terms ")
  for term in path_scope_terms(entity.path) {
    summary.write_string(term)
    summary.write_char(' ')
  }
  summary.to_string()
}

///|
fn recommendation_for(
  entity : LocalEntitySummary,
  action : NameAction,
  divergence : Double,
) -> String {
  match action {
    Keep => "keep"
    Hollow => "insufficient-content"
    Split => "split-or-move-" + entity.kind
    Rename =>
      if divergence > 0.8 {
        "rename-or-move-" + entity.kind
      } else {
        "review-" + entity.kind + "-name"
      }
  }
}

///|
fn assessment_for(action : NameAction) -> String {
  match action {
    Keep => "name-content-aligned"
    Hollow => "insufficient-content"
    Rename => "name-content-drift"
    Split => "overbroad-content"
  }
}

///|
fn effective_identity_action(
  entity : LocalEntitySummary,
  report : NameDivergence,
) -> NameAction {
  let action = report.get_action()
  if action != Keep && is_declaration_heavy_file(entity) {
    Hollow
  } else {
    action
  }
}

///|
fn is_declaration_heavy_file(entity : LocalEntitySummary) -> Bool {
  entity.kind == "file" &&
  entity.declaration_symbols > 0 &&
  entity.declaration_symbols >= entity.behavior_symbols
}

///|
fn assessment_priority(assessment : String) -> Int {
  match assessment {
    "name-content-drift" => 0
    "overbroad-content" => 1
    "insufficient-content" => 2
    _ => 3
  }
}

///|
fn bm25_similarity(left : String, right : String) -> Double {
  let docs = [
    @tokenizer.tokenize_for_tfidf(left),
    @tokenizer.tokenize_for_tfidf(right),
  ]
  let batch = @tfidf.BM25Batch::from_tokens(docs)
  batch.similarity(0, 1)
}

///|
fn symbol_summary_text(name : String, doc : String?) -> String {
  let summary = StringBuilder()
  summary.write_string(name)
  match doc {
    Some(text) if text.length() > 0 => {
      summary.write_string("\n")
      summary.write_string(text)
    }
    _ => ()
  }
  summary.to_string()
}

///|
fn append_feature_values(
  out : StringBuilder,
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry,
) -> Unit {
  let seen : Map[String, Bool] = Map([])
  for feat in @kgf_tokenize.tokenize_file(content, path, registry) {
    if !@kgf_tokenize.feature_has_value(feat) {
      continue
    }
    let value = @kgf_tokenize.feature_value(feat)
    if value.length() == 0 || seen.contains(value) {
      continue
    }
    seen[value] = true
    out.write_string(value)
    out.write_string("\n")
  }
}

///|
fn scoped_path_name(path : String, model : PathNameModel) -> String {
  let base = @config_paths.basename(path)
  let stem = file_stem(base)
  if model.basename_counts.get(base).unwrap_or(0) == 0 {
    return stem
  }
  let parent = @config_paths.basename(@config_paths.dirname(path))
  if parent.length() == 0 || parent == "." || parent == stem {
    stem
  } else {
    parent + " " + stem
  }
}

///|
fn file_stem(path : String) -> String {
  let base = @config_paths.basename(path)
  let ext = @config_paths.extension(base)
  if ext.length() > 0 && base.has_suffix(ext) {
    @config_paths.substring(base, 0, base.length() - ext.length())
  } else {
    base
  }
}

///|
fn path_scope_terms(path : String) -> Array[String] {
  let terms : Array[String] = []
  for segment in split_path(path) {
    let stem = file_stem(segment)
    if stem.length() > 0 && !terms.contains(stem) {
      terms.push(stem)
    }
  }
  terms
}

///|
fn split_path(path : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder()
  for ch in path {
    if ch == '/' || ch == '\\' {
      let part = buf.to_string()
      if part.length() > 0 {
        parts.push(part)
      }
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  let last = buf.to_string()
  if last.length() > 0 {
    parts.push(last)
  }
  parts
}

///|
fn limit_candidates(
  candidates : Array[IdentityAuditCandidate],
  limit : Int,
) -> Array[IdentityAuditCandidate] {
  if limit <= 0 || candidates.length() <= limit {
    return candidates
  }
  let result : Array[IdentityAuditCandidate] = []
  for i = 0; i < limit; i = i + 1 {
    result.push(candidates[i])
  }
  result
}

///|
fn max_divergence(candidates : Array[IdentityAuditCandidate]) -> Double {
  let mut max = 0.0
  for c in candidates {
    if c.divergence > max {
      max = c.divergence
    }
  }
  max
}
