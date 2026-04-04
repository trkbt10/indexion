///|
/// Vocabulary-level divergence detection between source code and documentation.
/// Complements symbol-level matching by comparing TF-IDF vocabulary distributions
/// to find terms present in source but absent from docs.

///|
/// Tokenized module group for vocabulary comparison.
struct TokenizedModuleGroup {
  module_path : String
  source_tokens : Array[String]
  doc_tokens : Array[String]
  doc_paths : Array[String]
}

///|
/// Compute vocabulary divergences for all module-documentation pairs.
/// Uses project-wide IDF to suppress ubiquitous terms (e.g., language primitives)
/// so that gap terms reflect concepts specific to each module.
pub fn compute_vocabulary_divergences(
  discovered_paths : Array[String],
  config : ReconcileConfig,
  registry : @registry.KGFRegistry,
) -> Array[VocabularyDivergence] {
  let groups = group_files_by_directory(discovered_paths, config, registry)
  // Phase 1: tokenize all files individually for project-wide DF,
  // then aggregate into per-group source/doc token arrays.
  let tokenized_groups : Array[TokenizedModuleGroup] = []
  let all_file_tokens : Array[Array[String]] = []
  for group in groups {
    if group.source_paths.is_empty() || group.doc_paths.is_empty() {
      continue
    }
    // Tokenize each file individually for fine-grained DF
    let source_per_file = tokenize_files_individually(
      group.source_paths,
      registry,
    )
    let doc_per_file = tokenize_files_individually(group.doc_paths, registry)
    // Contribute each file to project-wide DF
    for tokens in source_per_file {
      all_file_tokens.push(tokens)
    }
    for tokens in doc_per_file {
      all_file_tokens.push(tokens)
    }
    // Flatten into per-group arrays
    let source_tokens = flatten_token_arrays(source_per_file)
    let doc_tokens = flatten_token_arrays(doc_per_file)
    if source_tokens.is_empty() && doc_tokens.is_empty() {
      continue
    }
    tokenized_groups.push({
      module_path: group.module_path,
      source_tokens,
      doc_tokens,
      doc_paths: group.doc_paths,
    })
  }
  if all_file_tokens.is_empty() {
    return []
  }
  // Phase 2: build project-wide document frequency (per-file granularity)
  let project_df = @tfidf.build_document_frequency(all_file_tokens)
  let total_docs = all_file_tokens.length()
  // Phase 3: compute divergences using hybrid strategy.
  // - Cosine distance uses project-wide IDF (suppresses ubiquitous terms)
  // - Gap terms use module-local IDF (highlights package-specific concepts)
  //   then filtered by project-wide DF to remove ubiquitous terms
  let ubiquity_threshold = total_docs / 3 + 1
  let results : Array[VocabularyDivergence] = []
  for tg in tokenized_groups {
    // Module-local distance for gap term extraction
    let local_distance = @tfidf.calculate_tfidf_distance_from_tokens(
      tg.source_tokens,
      tg.doc_tokens,
    )
    if local_distance < config.vocabulary_divergence_threshold {
      continue
    }
    // Gap terms: module-local IDF for specificity, filtered by project-wide DF
    let local_df = @tfidf.build_document_frequency([
      tg.source_tokens,
      tg.doc_tokens,
    ])
    let source_vec = @tfidf.build_tfidf_vector(tg.source_tokens, local_df, 2)
    let doc_tf = @tfidf.build_term_frequency(tg.doc_tokens)
    let gap_terms = extract_gap_terms_filtered(
      source_vec, doc_tf, project_df, ubiquity_threshold,
    )
    if gap_terms.is_empty() {
      continue
    }
    let doc_path = if tg.doc_paths.length() == 1 {
      @config_paths.relative_to(config.target_dir, tg.doc_paths[0])
    } else {
      let first = @config_paths.relative_to(config.target_dir, tg.doc_paths[0])
      first + " (+" + (tg.doc_paths.length() - 1).to_string() + ")"
    }
    results.push({
      module_path: tg.module_path,
      doc_path,
      cosine_distance: local_distance,
      gap_terms,
      source_term_count: count_unique_tokens(tg.source_tokens),
      doc_term_count: count_unique_tokens(tg.doc_tokens),
    })
  }
  results.sort_by(fn(a, b) { b.cosine_distance.compare(a.cosine_distance) })
  results
}

///|
/// A group of source files and documentation files within a directory.
struct ModuleFileGroup {
  module_path : String
  source_paths : Array[String]
  doc_paths : Array[String]
}

///|
/// Group discovered files by their parent directory, separating source from docs.
fn group_files_by_directory(
  paths : Array[String],
  config : ReconcileConfig,
  registry : @registry.KGFRegistry,
) -> Array[ModuleFileGroup] {
  let groups : Map[String, ModuleFileGroup] = {}
  for path in paths {
    let dir = @config_paths.dirname(path)
    let rel_dir = @config_paths.relative_to(config.target_dir, dir)
    let module_path = if rel_dir.length() == 0 { "." } else { rel_dir }
    let group = match groups.get(module_path) {
      Some(g) => g
      None => {
        let g : ModuleFileGroup = {
          module_path,
          source_paths: [],
          doc_paths: [],
        }
        groups.set(module_path, g)
        g
      }
    }
    if is_document_path(path, config, registry) {
      group.doc_paths.push(path)
    } else {
      group.source_paths.push(path)
    }
  }
  let result : Array[ModuleFileGroup] = []
  for entry in groups {
    result.push(entry.1)
  }
  result
}

///|
/// Tokenize files individually, returning one token array per file.
fn tokenize_files_individually(
  paths : Array[String],
  registry : @registry.KGFRegistry,
) -> Array[Array[String]] {
  let result : Array[Array[String]] = []
  for path in paths {
    result.push(tokenize_file_group([path], registry))
  }
  result
}

///|
/// Flatten multiple token arrays into one.
fn flatten_token_arrays(arrays : Array[Array[String]]) -> Array[String] {
  let result : Array[String] = []
  for arr in arrays {
    for tok in arr {
      result.push(tok)
    }
  }
  result
}

///|
/// Tokenize a group of files for vocabulary comparison.
/// Uses two layers of token extraction:
/// - Standard TF-IDF tokens (Kind:value for identifiers, Kind for syntax)
/// - Vocabulary sub-tokens: words extracted from vocabulary_token_kinds
///   (doc comments, string literals) for detecting documentation gaps.
fn tokenize_file_group(
  paths : Array[String],
  registry : @registry.KGFRegistry,
) -> Array[String] {
  let all_tokens : Array[String] = []
  for path in paths {
    let content = @fs.read_file_to_string(path) catch { _ => continue }
    let spec_name = registry.detect_from_path(path)
    match spec_name {
      Some(name) =>
        match registry.get_spec(name) {
          Some(spec) => {
            let id_set = @kgf_features.build_identifier_set(spec~)
            let vocab_set = @kgf_features.build_vocabulary_token_set(spec~)
            let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
            let tokens = lexer.tokenize(content)
            for tok in tokens {
              let kind = tok.get_kind()
              let tfidf_token = @kgf_features.kgf_tok_to_tfidf_token(
                tok,
                id_set~,
              )
              let lowered = tfidf_token.to_lower()
              if lowered.length() >= 2 {
                all_tokens.push(lowered)
              }
              if vocab_set.contains(kind) {
                let text = tok.get_text()
                sub_tokenize_text(text, all_tokens)
              }
            }
          }
          None => ()
        }
      None => ()
    }
  }
  all_tokens
}

///|
/// Split text content into individual lowercase words (identifier-like tokens).
/// Adds words of length >= 3 to the output array with "vocab:" prefix.
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
/// Extract high-IDF terms present in source but absent from documentation.
/// Uses module-local TF-IDF for specificity, then filters out terms that appear
/// in too many files across the project (ubiquitous terms like "string", "array").
fn extract_gap_terms_filtered(
  source_vec : @tfidf.TfidfVector,
  doc_tf : Map[String, Int],
  project_df : Map[String, Int],
  ubiquity_threshold : Int,
) -> Array[String] {
  let value_weights : Map[String, Double] = {}
  for entry in source_vec.iter() {
    let term = entry.0
    let weight = entry.1
    if doc_tf.get(term).unwrap_or(0) == 0 {
      if is_meaningful_gap_term(term) {
        // Filter out ubiquitous terms: if this term appears in too many
        // project files, it's a language primitive, not a package concept.
        let project_freq = project_df.get(term).unwrap_or(0)
        if project_freq >= ubiquity_threshold {
          continue
        }
        let value = extract_token_value(term)
        let current = value_weights.get(value).unwrap_or(0.0)
        value_weights.set(value, current + weight)
      }
    }
  }
  let gaps : Array[(String, Double)] = []
  for entry in value_weights {
    gaps.push((entry.0, entry.1))
  }
  gaps.sort_by(fn(a, b) { b.1.compare(a.1) })
  let limit = if gaps.length() < 30 { gaps.length() } else { 30 }
  let result : Array[String] = []
  for i = 0; i < limit; i = i + 1 {
    result.push(gaps[i].0)
  }
  result
}

///|
/// Check whether a gap term is meaningful enough to report.
/// KGF tokens come as "Kind:value" (identifiers) or "Kind" (syntax tokens).
/// Only identifier-style tokens with a value part are meaningful gap terms.
fn is_meaningful_gap_term(term : String) -> Bool {
  if !has_colon(term) {
    return false
  }
  let value = extract_token_value(term)
  if value.length() < 3 {
    return false
  }
  let mut all_digits = true
  for ch in value {
    if ch < '0' || ch > '9' {
      all_digits = false
      break
    }
  }
  if all_digits {
    return false
  }
  true
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
/// Extract the value part from a KGF token string.
/// "Ident:config" -> "config", "vocab:template" -> "template"
fn extract_token_value(token : String) -> String {
  let mut colon_idx = -1
  for i = 0; i < token.length(); i = i + 1 {
    if token[i] == ':' {
      colon_idx = i
      break
    }
  }
  if colon_idx >= 0 && colon_idx < token.length() - 1 {
    token.substring(start=colon_idx + 1)
  } else {
    token
  }
}

///|
fn max_distance(divergences : Array[VocabularyDivergence]) -> Double {
  let mut max = 0.0
  for d in divergences {
    if d.cosine_distance > max {
      max = d.cosine_distance
    }
  }
  max
}

///|
fn count_unique_tokens(tokens : Array[String]) -> Int {
  let seen : Map[String, Bool] = {}
  for t in tokens {
    seen.set(t, true)
  }
  seen.length()
}
