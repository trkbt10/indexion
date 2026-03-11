///|
priv struct ModuleSignals {
  tokens : Map[String, Bool]
  anchors : Map[String, Bool]
}

///|
priv struct CandidateBuildResult {
  candidates : Array[ReconcileCandidate]
  module_covered_symbols : Int
}

///|
priv struct AggregateBucket {
  scope : String
  path : String
  status : String
  recommended_action : String
  candidate_count : Int
  logical_review_count : Int
  symbol_ids : Array[String]
  symbol_names : Array[String]
  doc_paths : Array[String]
  module_paths : Array[String]
}

///|
priv struct FragmentMatchSignals {
  exact_tokens : Map[String, Bool]
  reference_tokens : Map[String, Bool]
}

///|
fn is_ascii_upper(ch : Char) -> Bool {
  ch >= 'A' && ch <= 'Z'
}

///|
fn is_ascii_lower(ch : Char) -> Bool {
  ch >= 'a' && ch <= 'z'
}

///|
fn is_ascii_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn is_token_separator(ch : Char) -> Bool {
  ch == '_' || ch == '-' || ch == '.' || ch == '/' || ch == ':'
}

///|
fn is_token_char(ch : Char) -> Bool {
  is_ascii_upper(ch) ||
  is_ascii_lower(ch) ||
  is_ascii_digit(ch) ||
  is_token_separator(ch)
}

///|
fn is_all_digits(text : String) -> Bool {
  let chars = text.to_array()
  if chars.length() == 0 {
    return false
  }
  for ch in chars {
    if not(is_ascii_digit(ch)) {
      return false
    }
  }
  true
}

///|
fn is_specific_token(token : String) -> Bool {
  let normalized = lower_string(token)
  if normalized.length() < 2 || is_all_digits(normalized) {
    return false
  }
  if normalized == "db" ||
    normalized == "md" ||
    normalized == "kgf" ||
    normalized == "json" ||
    normalized == "toml" {
    return true
  }
  normalized.length() >= 5 ||
  normalized.contains("_") ||
  normalized.contains("-") ||
  normalized.contains(".")
}

///|
fn add_specific_token(tokens : Map[String, Bool], token : String) -> Unit {
  let normalized = lower_string(trim_string(token))
  if not(is_specific_token(normalized)) {
    return
  }
  tokens.set(normalized, true)
  if normalized.has_suffix("s") && normalized.length() >= 5 {
    let singular = substring(normalized, 0, normalized.length() - 1)
    if is_specific_token(singular) {
      tokens.set(singular, true)
    }
  }
}

///|
fn build_exact_token_index(text : String) -> Map[String, Bool] {
  let index : Map[String, Bool] = {}
  let raw_token : Array[Char] = []
  fn flush_raw(index : Map[String, Bool], raw_token : Array[Char]) -> Unit {
    if raw_token.length() == 0 {
      return
    }
    let raw = lower_string(String::from_array(raw_token))
    raw_token.clear()
    if raw.length() > 0 {
      index.set(raw, true)
    }
  }
  for ch in text.to_array() {
    if is_token_char(ch) {
      raw_token.push(ch)
    } else {
      flush_raw(index, raw_token)
    }
  }
  flush_raw(index, raw_token)
  index
}

///|
fn normalize_feature_token_text(text : String) -> String {
  let chars = text.to_array()
  if chars.length() >= 2 {
    let first = chars[0]
    let last = chars[chars.length() - 1]
    if (first == '`' && last == '`') ||
      (first == '"' && last == '"') ||
      (first == '\'' && last == '\'') ||
      (first == '[' && last == ']') ||
      (first == '(' && last == ')') ||
      (first == '{' && last == '}') {
      return substring(text, 1, text.length() - 1)
    }
  }
  text
}

///|
fn add_surface_term(tokens : Map[String, Bool], text : String) -> Unit {
  let normalized = normalize_feature_token_text(text)
  let raw_tokens = build_exact_token_index(normalized)
  for entry in raw_tokens {
    add_specific_token(tokens, entry.0)
    let part : Array[Char] = []
    fn flush_part(tokens : Map[String, Bool], part : Array[Char]) -> Unit {
      if part.length() == 0 {
        return
      }
      let raw = String::from_array(part)
      part.clear()
      add_specific_token(tokens, raw)
    }
    for ch in entry.0.to_array() {
      if is_token_separator(ch) {
        flush_part(tokens, part)
      } else {
        part.push(ch)
      }
    }
    flush_part(tokens, part)
  }
}

///|
fn file_stem(path : String) -> String {
  let base = @config_paths.basename(path)
  let ext = @config_paths.extension(path)
  if ext.length() > 0 && base.has_suffix(ext) {
    substring(base, 0, base.length() - ext.length())
  } else {
    base
  }
}

///|
fn build_feature_token_kinds(
  spec : @kgf_types.KGFSpec,
  feature_name : String,
) -> Map[String, Bool] {
  let kinds : Map[String, Bool] = {}
  match spec.get_feature(feature_name) {
    Some(values) =>
      for value in values {
        let normalized = lower_string(trim_string(value))
        if normalized.length() > 0 {
          kinds.set(normalized, true)
        }
      }
    None => ()
  }
  kinds
}

///|
fn add_feature_terms(
  tokens : Map[String, Bool],
  text : String,
  spec : @kgf_types.KGFSpec,
  feature_name : String,
) -> Bool {
  let selected_kinds = build_feature_token_kinds(spec, feature_name)
  if selected_kinds.is_empty() {
    return false
  }
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let lexed = lexer.tokenize(text)
  for tok in lexed {
    if selected_kinds.contains(lower_string(tok.get_kind())) {
      add_surface_term(tokens, tok.get_text())
    }
  }
  true
}

///|
fn add_path_anchor_terms(tokens : Map[String, Bool], text : String) -> Unit {
  add_surface_term(tokens, text)
}

///|
fn configured_doc_roots(doc_paths : Array[String]) -> Map[String, Bool] {
  let roots : Map[String, Bool] = {}
  for pattern in doc_paths {
    let normalized = @config_paths.normalize_path(pattern)
    let segment_chars : Array[Char] = []
    let mut saw_wildcard = false
    let mut added = false
    for ch in normalized.to_array() {
      if ch == '/' {
        let segment = String::from_array(segment_chars)
        segment_chars.clear()
        if segment.length() == 0 || segment == "." || segment == "**" {
          continue
        }
        if not(saw_wildcard) &&
          not(segment.contains("*")) &&
          @config_paths.extension(segment).length() == 0 {
          roots.set(segment, true)
        }
        added = true
        break
      }
      if ch == '*' {
        saw_wildcard = true
      }
      segment_chars.push(ch)
    }
    if added || segment_chars.length() == 0 {
      continue
    }
    let segment = String::from_array(segment_chars)
    if segment.length() == 0 ||
      segment == "." ||
      segment == "**" ||
      saw_wildcard ||
      segment.contains("*") ||
      @config_paths.extension(segment).length() > 0 {
      continue
    }
    roots.set(segment, true)
  }
  roots
}

///|
fn coverage_anchor_term(
  root_dir : String,
  path : String,
  doc_roots : Map[String, Bool],
) -> String {
  let fallback = @config_paths.basename(root_dir)
  let relative = @config_paths.relative_to(root_dir, path)
  let normalized = @config_paths.normalize_path(relative)
  if normalized == "." || normalized.length() == 0 {
    return fallback
  }
  let first_chars : Array[Char] = []
  for ch in normalized.to_array() {
    if ch == '/' {
      break
    }
    first_chars.push(ch)
  }
  let first = String::from_array(first_chars)
  if first.length() == 0 ||
    first == "." ||
    doc_roots.contains(first) ||
    @config_paths.extension(first).length() > 0 {
    fallback
  } else {
    first
  }
}

///|
fn build_module_signals(
  units : Array[CodeUnit],
  registry : @registry.KGFRegistry,
  root_dir : String,
  doc_roots : Map[String, Bool],
) -> Map[String, ModuleSignals] {
  let signals : Map[String, ModuleSignals] = {}
  for unit in units {
    let current = match signals.get(unit.module_path) {
      Some(existing) => existing
      None => {
        let seeded = { tokens: {}, anchors: {} }
        add_specific_token(
          seeded.anchors,
          coverage_anchor_term(root_dir, unit.module_path, doc_roots),
        )
        add_path_anchor_terms(seeded.tokens, unit.module_path)
        add_path_anchor_terms(seeded.tokens, file_stem(unit.module_path))
        let content = @fs.read_file_to_string(unit.module_path) catch {
          _ => ""
        }
        if content.length() > 0 {
          match registry.detect_from_path(unit.module_path) {
            Some(lang) =>
              match registry.get_spec(lang) {
                Some(spec) =>
                  if not(
                      add_feature_terms(
                        seeded.tokens,
                        content,
                        spec,
                        "coverage_token_kinds",
                      ),
                    ) {
                    add_surface_term(seeded.tokens, content)
                  }
                None => add_surface_term(seeded.tokens, content)
              }
            None => add_surface_term(seeded.tokens, content)
          }
        }
        seeded
      }
    }
    add_surface_term(current.tokens, unit.name)
    add_surface_term(current.tokens, unit.ns)
    add_path_anchor_terms(current.tokens, unit.module_id)
    signals.set(unit.module_path, current)
  }
  signals
}

///|
fn build_fragment_terms(
  fragments : Array[DocFragment],
  registry : @registry.KGFRegistry,
  root_dir : String,
  doc_roots : Map[String, Bool],
) -> Map[String, Map[String, Bool]] {
  let terms : Map[String, Map[String, Bool]] = {}
  for fragment in fragments {
    let current : Map[String, Bool] = {}
    let source_text = fragment.title + "\n" + fragment.content
    match registry.get_spec(fragment.spec) {
      Some(spec) =>
        if not(
            add_feature_terms(
              current, source_text, spec, "coverage_token_kinds",
            ),
          ) {
          add_surface_term(current, source_text)
        }
      None => add_surface_term(current, source_text)
    }
    add_specific_token(
      current,
      coverage_anchor_term(root_dir, fragment.path, doc_roots),
    )
    terms.set(fragment.id, current)
  }
  terms
}

///|
fn terms_overlap(left : String, right : String) -> Bool {
  if left == right {
    return true
  }
  let (shorter, longer) = if left.length() <= right.length() {
    (left, right)
  } else {
    (right, left)
  }
  shorter.length() >= 6 && longer.contains(shorter)
}

///|
fn shared_terms(
  left : Map[String, Bool],
  right : Map[String, Bool],
) -> Array[String] {
  let shared : Array[String] = []
  for left_entry in left {
    for right_entry in right {
      if terms_overlap(left_entry.0, right_entry.0) {
        shared.push(left_entry.0)
        break
      }
    }
  }
  shared.sort()
  shared
}

///|
fn build_module_coverage_index(
  units : Array[CodeUnit],
  fragments : Array[DocFragment],
  registry : @registry.KGFRegistry,
  root_dir : String,
  doc_paths : Array[String],
) -> Map[String, Bool] {
  let doc_roots = configured_doc_roots(doc_paths)
  let module_signals = build_module_signals(
    units, registry, root_dir, doc_roots,
  )
  let fragment_terms = build_fragment_terms(
    fragments, registry, root_dir, doc_roots,
  )
  let coverage : Map[String, Bool] = {}
  for module_entry in module_signals {
    let signals = module_entry.1
    let mut covered = false
    for fragment in fragments {
      let terms = match fragment_terms.get(fragment.id) {
        Some(value) => value
        None => continue
      }
      let overlaps = shared_terms(signals.tokens, terms)
      if overlaps.length() < 2 {
        continue
      }
      let anchor_hits = shared_terms(signals.anchors, terms)
      if anchor_hits.length() > 0 {
        covered = true
        break
      }
    }
    if covered {
      coverage.set(module_entry.0, true)
    }
  }
  coverage
}

///|
fn contains_term(text : String, term : String) -> Bool {
  let normalized_text = lower_string(text)
  let normalized_term = lower_string(term)
  normalized_text.contains(normalized_term)
}

///|
fn build_fragment_match_signals(
  fragments : Array[DocFragment],
  registry : @registry.KGFRegistry,
) -> Map[String, FragmentMatchSignals] {
  let signals : Map[String, FragmentMatchSignals] = {}
  for fragment in fragments {
    let source_text = fragment.title + "\n" + fragment.content
    let exact_tokens = build_exact_token_index(source_text)
    let reference_tokens : Map[String, Bool] = {}
    match registry.get_spec(fragment.spec) {
      Some(spec) => {
        let reference_kinds = build_feature_token_kinds(
          spec, "reference_token_kinds",
        )
        if reference_kinds.is_empty() {
          signals.set(fragment.id, { exact_tokens, reference_tokens })
          continue
        }
        let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
        let tokens = lexer.tokenize(source_text)
        for tok in tokens {
          let normalized_kind = lower_string(tok.get_kind())
          if reference_kinds.contains(normalized_kind) {
            let normalized = normalize_feature_token_text(tok.get_text())
            let token_index = build_exact_token_index(normalized)
            for entry in token_index {
              reference_tokens.set(entry.0, true)
            }
          }
        }
      }
      None => ()
    }
    signals.set(fragment.id, { exact_tokens, reference_tokens })
  }
  signals
}

///|
fn match_fragment(
  unit : CodeUnit,
  fragment : DocFragment,
  signals : FragmentMatchSignals,
  allow_file_fallback : Bool,
) -> (Int, String, Array[String]) {
  let source_text = fragment.title + "\n" + fragment.content
  let text = lower_string(source_text)
  let matched : Array[String] = []
  let qualified_dot = unit.ns + "." + unit.name
  let qualified_colon = unit.ns + "::" + unit.name
  if unit.ns.length() > 0 && contains_term(text, qualified_dot) {
    matched.push(qualified_dot)
    return (100, "qualified_symbol", matched)
  }
  if unit.ns.length() > 0 && contains_term(text, qualified_colon) {
    matched.push(qualified_colon)
    return (95, "qualified_symbol", matched)
  }
  if contains_term(text, "`" + lower_string(unit.name) + "`") {
    matched.push(unit.name)
    return (92, "inline_symbol", matched)
  }
  if signals.reference_tokens.contains(lower_string(unit.name)) {
    matched.push(unit.name)
    return (85, "symbol_name", matched)
  }
  if allow_file_fallback {
    let base = @config_paths.basename(unit.module_path)
    if base.length() > 0 && signals.exact_tokens.contains(lower_string(base)) {
      matched.push(base)
      return (45, "file_name", matched)
    }
  }
  (0, "none", matched)
}

///|
fn build_code_anchor(unit : CodeUnit) -> CodeAnchor {
  {
    symbol_id: unit.symbol_id,
    name: unit.name,
    kind: unit.kind,
    ns: unit.ns,
    module_path: unit.module_path,
    inline_doc: unit.inline_doc,
  }
}

///|
fn build_doc_anchor(fragment : DocFragment) -> DocAnchor {
  {
    fragment_id: fragment.id,
    path: fragment.path,
    spec: fragment.spec,
    kind: fragment.kind,
    title: fragment.title,
    preview: fragment.preview,
  }
}

///|
fn timestamp_for_path(
  root : String,
  path : String,
  config : ReconcileConfig,
) -> TimestampInfo {
  let repo_ok = config.git_preferred && @git.is_repo(root)
  if repo_ok {
    let git_time = @git.last_commit_seconds(root, path)
    let dirty = @git.status_dirty(root, path)
    if dirty {
      if config.mtime_fallback {
        match @git.file_mtime_seconds(path) {
          Some(seconds) =>
            return {
              epoch_seconds: Some(seconds),
              source: "mtime",
              is_dirty: true,
            }
          None => ()
        }
      }
    } else {
      match git_time {
        Some(seconds) =>
          return {
            epoch_seconds: Some(seconds),
            source: "git",
            is_dirty: false,
          }
        None => ()
      }
    }
  }
  if config.mtime_fallback {
    match @git.file_mtime_seconds(path) {
      Some(seconds) =>
        return {
          epoch_seconds: Some(seconds),
          source: "mtime",
          is_dirty: false,
        }
      None => ()
    }
  }
  TimestampInfo::unknown()
}

///|
fn time_relation(
  code_time : TimestampInfo,
  doc_time : TimestampInfo,
  threshold_seconds : Int,
) -> String {
  match (code_time.epoch_seconds, doc_time.epoch_seconds) {
    (Some(code_seconds), Some(doc_seconds)) => {
      let diff = code_seconds - doc_seconds
      if diff.abs() <= threshold_seconds {
        "in_sync"
      } else if diff > 0 {
        "doc_older"
      } else {
        "doc_newer"
      }
    }
    _ => "unknown"
  }
}

///|
fn classify_match_result(
  relation : String,
  mapping_confidence : Int,
  match_kind : String,
) -> (String, String, String) {
  match relation {
    "doc_older" =>
      (
        "stale_doc", "update_doc", "Implementation appears newer than the mapped document fragment.",
      )
    "doc_newer" =>
      if mapping_confidence >= 85 && match_kind != "file_name" {
        ("in_sync", "", "")
      } else {
        (
          "review_both", "review_both", "Document appears newer than the implementation and should be reviewed.",
        )
      }
    _ =>
      if mapping_confidence < 80 {
        (
          "review_mapping", "review_mapping", "Mapping is heuristic and should be reviewed.",
        )
      } else {
        ("in_sync", "", "")
      }
  }
}

///|
fn candidate_id(unit : CodeUnit, fragment : DocFragment?) -> String {
  let doc_key = match fragment {
    Some(value) => value.id
    None => "missing"
  }
  "cand:" + make_hash([unit.symbol_id, doc_key])
}

///|
fn build_candidates(
  units : Array[CodeUnit],
  fragments : Array[DocFragment],
  config : ReconcileConfig,
  registry : @registry.KGFRegistry,
) -> CandidateBuildResult {
  let candidates : Array[ReconcileCandidate] = []
  let module_coverage = build_module_coverage_index(
    units,
    fragments,
    registry,
    config.target_dir,
    config.documents.doc_paths,
  )
  let fragment_signals = build_fragment_match_signals(fragments, registry)
  let mut module_covered_symbols = 0
  for unit in units {
    let matches : Array[(Int, String, Array[String], DocFragment)] = []
    for fragment in fragments {
      let signals = match fragment_signals.get(fragment.id) {
        Some(value) => value
        None => { exact_tokens: {}, reference_tokens: {} }
      }
      let (score, match_kind, matched_terms) = match_fragment(
        unit,
        fragment,
        signals,
        config.allow_file_fallback,
      )
      if score > 0 {
        matches.push((score, match_kind, matched_terms, fragment))
      }
    }
    matches.sort_by(fn(a, b) {
      let score_cmp = b.0.compare(a.0)
      if score_cmp != 0 {
        score_cmp
      } else {
        a.3.id.compare(b.3.id)
      }
    })
    let has_inline_doc = unit.inline_doc is Some(_)
    if matches.length() == 0 {
      if not(has_inline_doc) {
        if module_coverage.contains(unit.module_path) {
          module_covered_symbols += 1
        } else {
          let code_time = timestamp_for_path(
            config.target_dir,
            unit.module_path,
            config,
          )
          candidates.push({
            id: candidate_id(unit, None),
            symbol_id: unit.symbol_id,
            status: "missing_doc",
            time_relation: "unmatched",
            mapping_confidence: 0,
            recommended_action: "update_doc",
            mechanical_digest: "",
            code_anchor: build_code_anchor(unit),
            doc_anchor: None,
            evidence: {
              matched_terms: [],
              match_kind: "none",
              reason: "No external document fragment matched this symbol.",
              code_time,
              doc_time: TimestampInfo::unknown(),
            },
            logical_review_key: None,
            logical_review_status: "pending",
            logical_review_reused: false,
            needs_logical_review: true,
          })
        }
      }
      continue
    }
    let best = matches[0]
    let doc_time = timestamp_for_path(config.target_dir, best.3.path, config)
    let code_time = timestamp_for_path(
      config.target_dir,
      unit.module_path,
      config,
    )
    let relation = time_relation(code_time, doc_time, config.threshold_seconds)
    let (status, action, reason) = classify_match_result(
      relation,
      best.0,
      best.1,
    )
    if status == "in_sync" {
      continue
    }
    candidates.push({
      id: candidate_id(unit, Some(best.3)),
      symbol_id: unit.symbol_id,
      status,
      time_relation: relation,
      mapping_confidence: best.0,
      recommended_action: action,
      mechanical_digest: "",
      code_anchor: build_code_anchor(unit),
      doc_anchor: Some(build_doc_anchor(best.3)),
      evidence: {
        matched_terms: best.2,
        match_kind: best.1,
        reason,
        code_time,
        doc_time,
      },
      logical_review_key: None,
      logical_review_status: "pending",
      logical_review_reused: false,
      needs_logical_review: true,
    })
  }
  candidates.sort_by(fn(a, b) {
    let status_cmp = status_priority(a.status).compare(
      status_priority(b.status),
    )
    if status_cmp != 0 {
      status_cmp
    } else {
      b.mapping_confidence.compare(a.mapping_confidence)
    }
  })
  { candidates, module_covered_symbols }
}

///|
fn limit_candidates(
  candidates : Array[ReconcileCandidate],
  max_candidates : Int,
) -> Array[ReconcileCandidate] {
  if candidates.length() <= max_candidates {
    return candidates
  }
  let limited : Array[ReconcileCandidate] = []
  for i = 0; i < max_candidates; i = i + 1 {
    limited.push(candidates[i])
  }
  limited
}

///|
fn build_summary(
  units : Array[CodeUnit],
  fragments : Array[DocFragment],
  candidates : Array[ReconcileCandidate],
  aggregate_suggestions : Array[ReconcileAggregateSuggestion],
  module_covered_symbols : Int,
  logical_reviews : Array[LogicalReviewTask],
  reused_logical_reviews : Int,
) -> ReconcileSummary {
  let mut symbols_with_inline_doc = 0
  let mut module_suggestions = 0
  let mut project_suggestions = 0
  for unit in units {
    if unit.inline_doc is Some(_) {
      symbols_with_inline_doc += 1
    }
  }
  for group in aggregate_suggestions {
    if group.scope == "module" {
      module_suggestions += 1
    } else if group.scope == "project" {
      project_suggestions += 1
    }
  }
  let mut missing_doc = 0
  let mut stale_doc = 0
  let mut review_mapping = 0
  let mut review_both = 0
  let mut pending_logical_reviews = 0
  let mut completed_logical_reviews = 0
  let mut new_logical_reviews = 0
  for task in logical_reviews {
    if task.reused {
      ()
    } else {
      new_logical_reviews += 1
    }
  }
  for candidate in candidates {
    match candidate.status {
      "missing_doc" => missing_doc += 1
      "stale_doc" => stale_doc += 1
      "review_both" => review_both += 1
      _ => review_mapping += 1
    }
    if candidate.logical_review_status == "pending" {
      pending_logical_reviews += 1
    } else if candidate.logical_review_status != "disabled" {
      completed_logical_reviews += 1
    }
  }
  {
    total_symbols: units.length(),
    symbols_with_inline_doc,
    module_covered_symbols,
    total_doc_fragments: fragments.length(),
    total_candidates: candidates.length(),
    total_aggregate_suggestions: aggregate_suggestions.length(),
    module_suggestions,
    project_suggestions,
    missing_doc,
    stale_doc,
    review_mapping,
    review_both,
    pending_logical_reviews,
    new_logical_reviews,
    reused_logical_reviews,
    completed_logical_reviews,
  }
}

///|
fn push_unique(values : Array[String], value : String) -> Unit {
  if value.length() == 0 || contains_string(values, value) {
    return
  }
  values.push(value)
}

///|
fn aggregate_bucket(
  scope : String,
  path : String,
  status : String,
  recommended_action : String,
) -> AggregateBucket {
  {
    scope,
    path,
    status,
    recommended_action,
    candidate_count: 0,
    logical_review_count: 0,
    symbol_ids: [],
    symbol_names: [],
    doc_paths: [],
    module_paths: [],
  }
}

///|
fn aggregate_key(scope : String, path : String, status : String) -> String {
  scope + "\u0000" + path + "\u0000" + status
}

///|
fn project_group_path(
  root_dir : String,
  module_path : String,
  project_markers : Array[String],
) -> String? {
  match
    @config_paths.find_nearest_marker_dir(
      root_dir, module_path, project_markers,
    ) {
    Some(dir) => Some(@config_paths.relative_to(root_dir, dir))
    None => None
  }
}

///|
fn add_candidate_to_bucket(
  buckets : Map[String, AggregateBucket],
  key : String,
  scope : String,
  path : String,
  candidate : ReconcileCandidate,
  logical_review_count_delta : Int,
) -> Unit {
  let current = match buckets.get(key) {
    Some(existing) => existing
    None =>
      aggregate_bucket(
        scope,
        path,
        candidate.status,
        candidate.recommended_action,
      )
  }
  let updated = {
    ..current,
    candidate_count: current.candidate_count + 1,
    logical_review_count: current.logical_review_count +
    logical_review_count_delta,
  }
  push_unique(updated.symbol_ids, candidate.symbol_id)
  push_unique(updated.symbol_names, candidate.code_anchor.name)
  push_unique(updated.module_paths, candidate.code_anchor.module_path)
  match candidate.doc_anchor {
    Some(anchor) => push_unique(updated.doc_paths, anchor.path)
    None => ()
  }
  buckets.set(key, updated)
}

///|
fn sort_aggregate_suggestions(
  suggestions : Array[ReconcileAggregateSuggestion],
) -> Array[ReconcileAggregateSuggestion] {
  let sorted = suggestions.copy()
  sorted.sort_by(fn(a, b) {
    let count_cmp = b.candidate_count.compare(a.candidate_count)
    if count_cmp != 0 {
      count_cmp
    } else {
      let status_cmp = status_priority(a.status).compare(
        status_priority(b.status),
      )
      if status_cmp != 0 {
        status_cmp
      } else {
        a.path.compare(b.path)
      }
    }
  })
  sorted
}

///|
fn project_doc_paths(
  fragments : Array[DocFragment],
  root_dir : String,
  project_markers : Array[String],
) -> Map[String, Array[String]] {
  let index : Map[String, Array[String]] = {}
  for fragment in fragments {
    match project_group_path(root_dir, fragment.path, project_markers) {
      Some(project_path) => {
        let paths = match index.get(project_path) {
          Some(existing) => existing
          None => []
        }
        push_unique(paths, @config_paths.relative_to(root_dir, fragment.path))
        index.set(project_path, paths)
      }
      None => ()
    }
  }
  index
}

///|
fn build_aggregate_suggestions(
  raw_candidates : Array[ReconcileCandidate],
  visible_candidates : Array[ReconcileCandidate],
  fragments : Array[DocFragment],
  root_dir : String,
  project_markers : Array[String],
) -> Array[ReconcileAggregateSuggestion] {
  let visible_index : Map[String, ReconcileCandidate] = {}
  for candidate in visible_candidates {
    visible_index.set(candidate.id, candidate)
  }
  let project_docs = project_doc_paths(fragments, root_dir, project_markers)
  let module_buckets : Map[String, AggregateBucket] = {}
  let project_buckets : Map[String, AggregateBucket] = {}
  for candidate in raw_candidates {
    let logical_review_count_delta = match visible_index.get(candidate.id) {
      Some(visible) => if visible.needs_logical_review { 1 } else { 0 }
      None => 0
    }
    let module_path = @config_paths.relative_to(
      root_dir,
      candidate.code_anchor.module_path,
    )
    add_candidate_to_bucket(
      module_buckets,
      aggregate_key("module", module_path, candidate.status),
      "module",
      module_path,
      candidate,
      logical_review_count_delta,
    )
    match
      project_group_path(
        root_dir,
        candidate.code_anchor.module_path,
        project_markers,
      ) {
      Some(project_path) => {
        add_candidate_to_bucket(
          project_buckets,
          aggregate_key("project", project_path, candidate.status),
          "project",
          project_path,
          candidate,
          logical_review_count_delta,
        )
        match project_docs.get(project_path) {
          Some(paths) => {
            let project_key = aggregate_key(
              "project",
              project_path,
              candidate.status,
            )
            let bucket = project_buckets.get(project_key).unwrap()
            for path in paths {
              push_unique(bucket.doc_paths, path)
            }
            project_buckets.set(project_key, bucket)
          }
          None => ()
        }
      }
      None => ()
    }
  }
  let suggestions : Array[ReconcileAggregateSuggestion] = []
  for entry in module_buckets {
    let bucket = entry.1
    if bucket.candidate_count < 2 {
      continue
    }
    suggestions.push({
      id: "agg:" + make_hash([bucket.scope, bucket.path, bucket.status]),
      scope: bucket.scope,
      path: bucket.path,
      status: bucket.status,
      recommended_action: bucket.recommended_action,
      candidate_count: bucket.candidate_count,
      logical_review_count: bucket.logical_review_count,
      symbol_ids: sort_strings(bucket.symbol_ids),
      symbol_names: sort_strings(bucket.symbol_names),
      doc_paths: sort_strings(bucket.doc_paths),
    })
  }
  for entry in project_buckets {
    let bucket = entry.1
    if bucket.candidate_count < 3 || bucket.module_paths.length() < 2 {
      continue
    }
    suggestions.push({
      id: "agg:" + make_hash([bucket.scope, bucket.path, bucket.status]),
      scope: bucket.scope,
      path: bucket.path,
      status: bucket.status,
      recommended_action: bucket.recommended_action,
      candidate_count: bucket.candidate_count,
      logical_review_count: bucket.logical_review_count,
      symbol_ids: sort_strings(bucket.symbol_ids),
      symbol_names: sort_strings(bucket.symbol_names),
      doc_paths: sort_strings(bucket.doc_paths),
    })
  }
  sort_aggregate_suggestions(suggestions)
}

///|
fn collapse_aggregate_only_candidates(
  candidates : Array[ReconcileCandidate],
  aggregate_suggestions : Array[ReconcileAggregateSuggestion],
  root_dir : String,
  project_markers : Array[String],
) -> Array[ReconcileCandidate] {
  let suppressed_modules : Map[String, Bool] = {}
  let suppressed_projects : Map[String, Bool] = {}
  for group in aggregate_suggestions {
    if group.status != "missing_doc" || group.doc_paths.length() == 0 {
      continue
    }
    if group.scope == "module" {
      suppressed_modules.set(group.path, true)
    } else if group.scope == "project" {
      suppressed_projects.set(group.path, true)
    }
  }
  let collapsed : Array[ReconcileCandidate] = []
  for candidate in candidates {
    if candidate.status != "missing_doc" || candidate.doc_anchor is Some(_) {
      collapsed.push(candidate)
      continue
    }
    let module_path = @config_paths.relative_to(
      root_dir,
      candidate.code_anchor.module_path,
    )
    let module_suppressed = suppressed_modules.contains(module_path)
    let project_suppressed = match
      project_group_path(
        root_dir,
        candidate.code_anchor.module_path,
        project_markers,
      ) {
      Some(project_path) => suppressed_projects.contains(project_path)
      None => false
    }
    if module_suppressed || project_suppressed {
      continue
    }
    collapsed.push(candidate)
  }
  collapsed
}
