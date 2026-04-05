///|
/// Vocabulary-level divergence detection between source code and documentation.
/// Complements symbol-level matching by comparing TF-IDF vocabulary distributions
/// to find terms present in source but absent from docs.

///|
/// Tokenized module group for vocabulary comparison.
priv struct TokenizedModuleGroup {
  module_path : String
  source_tokens : Array[Array[String]]
  doc_tokens : Array[Array[String]]
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
  let tokenized_groups : Array[TokenizedModuleGroup] = []
  for group in groups {
    if group.source_paths.is_empty() || group.doc_paths.is_empty() {
      continue
    }
    let source_per_file = tokenize_files_individually(
      group.source_paths,
      registry,
    )
    let doc_per_file = tokenize_files_individually(group.doc_paths, registry)
    if source_per_file.is_empty() && doc_per_file.is_empty() {
      continue
    }
    tokenized_groups.push({
      module_path: group.module_path,
      source_tokens: source_per_file,
      doc_tokens: doc_per_file,
      doc_paths: group.doc_paths,
    })
  }
  let results : Array[VocabularyDivergence] = []
  let gap_config : @vocab.GapConfig = { min_value_length: 3, max_terms: 15 }
  for tg in tokenized_groups {
    let result = @vocab.measure_divergence(
      tg.source_tokens,
      tg.doc_tokens,
      gap_config,
    )
    if result.cosine_distance < config.vocabulary_divergence_threshold {
      continue
    }
    if result.gap_terms.is_empty() {
      continue
    }
    let gap_values : Array[String] = result.gap_terms.map(fn(g) { g.value })
    let doc_path = if tg.doc_paths.length() == 1 {
      @config_paths.relative_to(config.target_dir, tg.doc_paths[0])
    } else {
      let first = @config_paths.relative_to(config.target_dir, tg.doc_paths[0])
      first + " (+" + (tg.doc_paths.length() - 1).to_string() + ")"
    }
    results.push({
      module_path: tg.module_path,
      doc_path,
      cosine_distance: result.cosine_distance,
      gap_terms: gap_values,
      source_term_count: count_unique_tokens(tg.source_tokens.flatten()),
      doc_term_count: count_unique_tokens(tg.doc_tokens.flatten()),
    })
  }
  results.sort_by(fn(a, b) { b.cosine_distance.compare(a.cosine_distance) })
  results
}

///|
/// A group of source files and documentation files within a directory.
priv struct ModuleFileGroup {
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
    let content = @fs.read_file_to_string(path) catch { _ => continue }
    let tokens = @kgf_tokenize.tokenize_file(content, path, registry)
    result.push(tokens)
  }
  result
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
