///|
/// Spec-to-implementation conformance analysis using TF-IDF vocabulary comparison.
///
/// Approach: tokenize both spec documents and implementation files using KGF,
/// build TF-IDF vectors, compute cosine distance, and extract gap terms
/// (terms present in spec but absent from implementation). Gap terms represent
/// specification concepts that may be missing from the implementation.
///
/// This is the reverse of reconcile's vocabulary divergence (which finds
/// code terms missing from docs). Here we find spec terms missing from code.

///|
/// Run the full analysis pipeline. Returns the verify report.
fn run_analysis(config : VerifyConfig) -> VerifyReport {
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir=config.specs_dir,
    target_dir=config.target_dir,
  )
  // Discover spec files
  let spec_paths = expand_spec_patterns(config.spec_patterns)
  if spec_paths.length() == 0 {
    return empty_report(config, spec_paths, [])
  }
  // Discover implementation files
  let kgf_ignore = registry.collect_ignore_patterns()
  let discover_opts = @pipeline.DiscoverOptions::new(
    kgf_ignore~,
    root_dir=config.target_dir,
  )
  let impl_paths = @pipeline.discover_files(
    [config.target_dir],
    discover_opts,
  )
  // Tokenize spec and impl files
  let spec_tokens = tokenize_file_set(spec_paths, registry)
  let impl_tokens = tokenize_file_set(impl_paths, registry)
  if spec_tokens.length() == 0 {
    return empty_report(config, spec_paths, impl_paths)
  }
  // Build document frequency across all files (both spec and impl)
  let all_file_tokens : Array[Array[String]] = []
  for t in spec_tokens {
    all_file_tokens.push(t)
  }
  for t in impl_tokens {
    all_file_tokens.push(t)
  }
  let project_df = @tfidf.build_document_frequency(all_file_tokens)
  let total_docs = all_file_tokens.length()
  // Flatten spec and impl tokens
  let spec_flat = flatten_tokens(spec_tokens)
  let impl_flat = flatten_tokens(impl_tokens)
  // Compute overall cosine distance between spec and impl vocabularies
  let cosine_dist = @tfidf.calculate_tfidf_distance_from_tokens(
    spec_flat, impl_flat,
  )
  // Extract gap terms: spec terms not found in implementation
  let local_df = @tfidf.build_document_frequency([spec_flat, impl_flat])
  let spec_vec = @tfidf.build_tfidf_vector(spec_flat, local_df, 2)
  let impl_tf = @tfidf.build_term_frequency(impl_flat)
  let ubiquity_threshold = total_docs / 3 + 1
  let gap_terms = extract_gap_terms(
    spec_vec, impl_tf, project_df, ubiquity_threshold,
  )
  // Apply focus filter
  let filtered_gaps = apply_focus(gap_terms, config.focus)
  // Limit
  let limited_gaps = if filtered_gaps.length() > config.max_candidates {
    let result : Array[GapTerm] = []
    for i = 0; i < config.max_candidates; i = i + 1 {
      result.push(filtered_gaps[i])
    }
    result
  } else {
    filtered_gaps
  }
  // Convert to report items
  let items = gap_terms_to_items(limited_gaps, spec_paths)
  let summary = build_summary(items, cosine_dist)
  let used_specs = collect_used_specs(spec_paths, impl_paths, registry)
  {
    version: "spec-verify-v1",
    generated_at: 0,
    config: {
      spec_paths: spec_paths.copy(),
      target_dir: config.target_dir,
      focus: config.focus,
      max_candidates: config.max_candidates,
    },
    summary: {
      ..summary,
      spec_files: spec_paths.length(),
      impl_files: impl_paths.length(),
      spec_symbols: spec_flat.length(),
    },
    items,
    used_specs,
  }
}

///|
/// A term found in spec but absent from implementation.
struct GapTerm {
  term : String
  value : String
  weight : Double
  kind : String
} derive(Eq, Show)

///|
/// Tokenize a set of files individually, returning one token array per file.
fn tokenize_file_set(
  paths : Array[String],
  registry : @registry.KGFRegistry,
) -> Array[Array[String]] {
  let result : Array[Array[String]] = []
  for path in paths {
    let content = @fs.read_file_to_string(path) catch { _ => continue }
    let tokens = tokenize_single_file(content, path, registry)
    if tokens.length() > 0 {
      result.push(tokens)
    }
  }
  result
}

///|
/// Tokenize a single file into TF-IDF tokens using KGF.
///
/// For document files (markdown, HTML), code examples embedded in code fences
/// are re-tokenized with the fence language's KGF spec, producing the same
/// identifier tokens (e.g., `Ident:listChanged`) that would appear if the
/// code were in a standalone file. This enables cross-format vocabulary matching
/// without any custom normalization layer.
///
/// Reference tokens (e.g., INLINE_CODE in markdown) are emitted as identifiers
/// of the enclosing spec, bridging the gap between documentation references
/// and implementation identifiers.
fn tokenize_single_file(
  content : String,
  path : String,
  registry : @registry.KGFRegistry,
) -> Array[String] {
  let all_tokens : Array[String] = []
  let spec_name = registry.detect_from_path(path)
  match spec_name {
    Some(name) =>
      match registry.get_spec(name) {
        Some(spec) => {
          let id_set = @kgf_features.build_identifier_set(spec~)
          let vocab_set = @kgf_features.build_vocabulary_token_set(spec~)
          let ref_set = build_feature_set(spec, "reference_token_kinds")
          let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
          let tokens = lexer.tokenize(content)
          let mut in_code_fence = false
          let mut fence_spec : @kgf_types.KGFSpec? = None
          for tok in tokens {
            let kind = tok.get_kind()
            if kind == "CODE_FENCE" {
              if !(in_code_fence) {
                in_code_fence = true
                fence_spec = resolve_fence_spec(tok, registry)
              } else {
                in_code_fence = false
                fence_spec = None
              }
              continue
            }
            // Standard TF-IDF token from the file's own KGF
            let tfidf_token = @kgf_features.kgf_tok_to_tfidf_token(
              tok, id_set~,
            )
            let lowered = tfidf_token.to_lower()
            if lowered.length() >= 2 {
              all_tokens.push(lowered)
            }
            // Code fence: re-tokenize TEXT with the fence language's KGF.
            // This turns e.g. `"method": "initialize"` into `StringLit:initialize`
            // using the json KGF, producing identical tokens to a standalone .json file.
            if in_code_fence && kind == "TEXT" {
              match fence_spec {
                Some(fspec) =>
                  retokenize_embedded(tok.get_text(), fspec, all_tokens)
                None => ()
              }
              continue
            }
            // Reference tokens (e.g., INLINE_CODE): emit the value as an
            // identifier token. `listChanged` becomes `Ident:listChanged`,
            // matching the same token from implementation code.
            if ref_set.contains(kind) {
              let value = tok.get_value()
              if value.length() >= 2 {
                all_tokens.push("Ident:" + value.to_lower())
              }
            }
            // Vocabulary sub-tokens for natural language content
            if vocab_set.contains(kind) {
              sub_tokenize_text(tok.get_text(), all_tokens)
            }
          }
        }
        None => ()
      }
    None => ()
  }
  all_tokens
}

///|
/// Build a feature set (Map[String, Bool]) from a KGF spec feature name.
fn build_feature_set(
  spec : @kgf_types.KGFSpec,
  feature_name : String,
) -> Map[String, Bool] {
  let set : Map[String, Bool] = {}
  match spec.get_feature(feature_name) {
    Some(kinds) =>
      for kind in kinds {
        set[kind] = true
      }
    None => ()
  }
  set
}

///|
/// Resolve the KGF spec for a CODE_FENCE's language.
/// Uses the token's captured value (language hint) to look up the registry.
/// Returns None if the language is unrecognized or has no identifier tokens.
fn resolve_fence_spec(
  tok : @kgf_types.Tok,
  registry : @registry.KGFRegistry,
) -> @kgf_types.KGFSpec? {
  let lang_hint = tok.get_value().to_lower()
  if lang_hint.length() == 0 {
    return None
  }
  let spec = match registry.get_spec(lang_hint) {
    Some(s) => Some(s)
    None =>
      match registry.detect_from_path("_." + lang_hint) {
        Some(detected_lang) => registry.get_spec(detected_lang)
        None => None
      }
  }
  match spec {
    Some(s) => {
      let id_kinds = @kgf_features.build_identifier_set(spec=s)
      if id_kinds.is_empty() { None } else { Some(s) }
    }
    None => None
  }
}

///|
/// Re-tokenize embedded code using a different KGF spec.
/// The text (from a code fence) is tokenized with the fence language's lexer,
/// and the resulting tokens are converted to TF-IDF format and appended
/// to the output.
fn retokenize_embedded(
  text : String,
  spec : @kgf_types.KGFSpec,
  output : Array[String],
) -> Unit {
  let id_set = @kgf_features.build_identifier_set(spec~)
  let vocab_set = @kgf_features.build_vocabulary_token_set(spec~)
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(text)
  for tok in tokens {
    let tfidf_token = @kgf_features.kgf_tok_to_tfidf_token(tok, id_set~)
    let lowered = tfidf_token.to_lower()
    if lowered.length() >= 2 {
      output.push(lowered)
    }
    if vocab_set.contains(tok.get_kind()) {
      sub_tokenize_text(tok.get_text(), output)
    }
  }
}

///|
/// Split text content into individual lowercase words.
/// Emits vocab: tokens for vocabulary-level comparison.
fn sub_tokenize_text(text : String, output : Array[String]) -> Unit {
  let buf = StringBuilder::new()
  for ch in text {
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' {
      buf.write_char(ch)
    } else {
      let word = buf.to_string().to_lower()
      if word.length() >= 3 {
        output.push("vocab:" + word)
      }
      buf.reset()
    }
  }
  let last = buf.to_string().to_lower()
  if last.length() >= 3 {
    output.push("vocab:" + last)
  }
}

///|
/// Flatten multiple token arrays into one.
fn flatten_tokens(arrays : Array[Array[String]]) -> Array[String] {
  let result : Array[String] = []
  for arr in arrays {
    for tok in arr {
      result.push(tok)
    }
  }
  result
}

///|
/// Extract gap terms: terms with high TF-IDF weight in spec that are
/// absent from implementation, filtered by project-wide document frequency
/// to suppress ubiquitous terms.
fn extract_gap_terms(
  spec_vec : @tfidf.TfidfVector,
  impl_tf : Map[String, Int],
  project_df : Map[String, Int],
  ubiquity_threshold : Int,
) -> Array[GapTerm] {
  // Build a set of values present in the implementation across all prefixes.
  // This enables cross-prefix matching: if impl has "Ident:jsonrpc" and
  // spec has "StringLit:jsonrpc", the value "jsonrpc" is considered present.
  let impl_values : Map[String, Bool] = {}
  for kv in impl_tf {
    let value = extract_token_value(kv.0)
    if value.length() >= 2 {
      impl_values[value] = true
    }
  }
  let value_weights : Map[String, (Double, String)] = {}
  for entry in spec_vec.iter() {
    let term = entry.0
    let weight = entry.1
    // Only consider identifier-style tokens (Kind:value), not vocabulary
    // sub-tokens (vocab:word) which represent natural language words.
    if !(has_colon(term)) || term.has_prefix("vocab:") {
      continue
    }
    let value = extract_token_value(term)
    if value.length() < 2 {
      continue
    }
    // Cross-prefix check: skip if the VALUE exists in impl under any prefix
    if impl_values.contains(value) {
      continue
    }
    // Also skip if the exact term exists in impl
    if impl_tf.get(term).unwrap_or(0) > 0 {
      continue
    }
    // Filter ubiquitous terms
    let freq = project_df.get(term).unwrap_or(0)
    if freq >= ubiquity_threshold {
      continue
    }
    // Skip pure numeric values (including negative numbers like error codes)
    if is_numeric_value(value) {
      continue
    }
    let kind = extract_token_kind(term)
    match value_weights.get(value) {
      Some((existing_weight, _existing_kind)) =>
        if weight > existing_weight {
          value_weights[value] = (weight, kind)
        }
      None => value_weights[value] = (weight, kind)
    }
  }
  let gaps : Array[GapTerm] = []
  for vw in value_weights {
    let value = vw.0
    let (weight, kind) = vw.1
    gaps.push({ term: kind + ":" + value, value, weight, kind })
  }
  // Sort by weight descending
  gaps.sort_by(fn(a, b) { b.weight.compare(a.weight) })
  // Apply Kneedle thresholding to separate meaningful gaps from noise
  if gaps.length() <= 1 {
    return gaps
  }
  let weights : Array[Double] = gaps.map(fn(g) { g.weight })
  let cutoff = @stats.kneedle_threshold_index(weights)
  let limit = if cutoff < gaps.length() { cutoff } else { gaps.length() }
  if limit == 0 {
    return []
  }
  let result : Array[GapTerm] = []
  for i = 0; i < limit; i = i + 1 {
    result.push(gaps[i])
  }
  result
}

///|
/// Extract the value part from a TF-IDF token.
/// "Ident:config" → "config", "vocab:template" → "template"
fn extract_token_value(token : String) -> String {
  for i = 0; i < token.length(); i = i + 1 {
    if token[i] == ':' && i < token.length() - 1 {
      return token[i + 1:].to_string()
    }
  }
  token
}

///|
/// Extract the kind part from a TF-IDF token.
/// "Ident:config" → "Ident", "vocab:template" → "vocab"
fn extract_token_kind(token : String) -> String {
  for i = 0; i < token.length(); i = i + 1 {
    if token[i] == ':' {
      return token[:i].to_string()
    }
  }
  token
}

///|
fn has_colon(s : String) -> Bool {
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == ':' {
      return true
    }
  }
  false
}

///|
/// Check if a string is a pure numeric value (digits, optionally with leading
/// minus sign). These are not meaningful vocabulary terms.
fn is_numeric_value(s : String) -> Bool {
  if s.length() == 0 {
    return true
  }
  let mut start = 0
  if s[0] == '-' {
    start = 1
  }
  if start >= s.length() {
    return false
  }
  for i = start; i < s.length(); i = i + 1 {
    let c = s[i]
    if c < '0' || c > '9' {
      return false
    }
  }
  true
}

///|
/// Apply focus filter to gap terms.
fn apply_focus(gaps : Array[GapTerm], focus : String) -> Array[GapTerm] {
  if focus == "all" {
    return gaps
  }
  gaps.filter(fn(g) { g.kind == focus })
}

///|
/// Convert gap terms to VerifyItems for the report.
fn gap_terms_to_items(
  gaps : Array[GapTerm],
  _spec_paths : Array[String],
) -> Array[VerifyItem] {
  gaps.map(
    fn(g) {
      {
        status: "missing",
        spec_symbol: {
          identifier: g.value,
          kind: g.kind,
          context: "",
          source_path: "",
          source_line: 0,
        },
        evidence: {
          found_in: [],
          match_kind: "",
          note: "spec term not found in implementation (weight: " +
            format_weight(g.weight) +
            ")",
        },
      }
    },
  )
}

///|
fn format_weight(w : Double) -> String {
  let scaled = w * 10000.0
  let int_part = scaled.to_int()
  let major = int_part / 100
  let minor = int_part % 100
  major.to_string() +
  "." +
  (if minor < 10 { "0" } else { "" }) +
  minor.to_string() +
  "e-2"
}

///|
/// Build summary from items and cosine distance.
fn build_summary(items : Array[VerifyItem], cosine_dist : Double) -> VerifySummary {
  let mut missing = 0
  let mut dead = 0
  let mut drift = 0
  for item in items {
    match item.status {
      "missing" => missing += 1
      "dead" => dead += 1
      "drift" => drift += 1
      _ => ()
    }
  }
  {
    spec_files: 0,
    spec_symbols: 0,
    impl_files: 0,
    cosine_distance: cosine_dist,
    gap_count: missing,
    matched: 0,
    missing,
    dead,
    drift,
  }
}

///|
/// Expand glob patterns into deduplicated file paths.
fn expand_spec_patterns(patterns : Array[String]) -> Array[String] {
  let result : Array[String] = []
  let seen : Map[String, Bool] = {}
  for pattern in patterns {
    let paths = @glob.expand_glob(pattern)
    for path in paths {
      if !(seen.contains(path)) {
        seen[path] = true
        result.push(path)
      }
    }
  }
  result
}

///|
/// Collect KGF spec names used for the given file paths.
fn collect_used_specs(
  spec_paths : Array[String],
  impl_paths : Array[String],
  registry : @registry.KGFRegistry,
) -> Array[String] {
  let seen : Map[String, Bool] = {}
  let result : Array[String] = []
  let all_paths = spec_paths + impl_paths
  for path in all_paths {
    match registry.detect_from_path(path) {
      Some(lang) =>
        if !(seen.contains(lang)) {
          seen[lang] = true
          result.push(lang)
        }
      None => ()
    }
  }
  result
}

///|
fn empty_report(
  config : VerifyConfig,
  spec_paths : Array[String],
  impl_paths : Array[String],
) -> VerifyReport {
  {
    version: "spec-verify-v1",
    generated_at: 0,
    config: {
      spec_paths: spec_paths.copy(),
      target_dir: config.target_dir,
      focus: config.focus,
      max_candidates: config.max_candidates,
    },
    summary: {
      spec_files: spec_paths.length(),
      spec_symbols: 0,
      impl_files: impl_paths.length(),
      cosine_distance: 0.0,
      gap_count: 0,
      matched: 0,
      missing: 0,
      dead: 0,
      drift: 0,
    },
    items: [],
    used_specs: [],
  }
}
