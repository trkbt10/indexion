///|
/// Spec-to-implementation conformance analysis using TF-IDF vocabulary comparison.
///
/// Approach: tokenize both spec documents and implementation files using KGF,
/// measure vocabulary divergence, and report gap terms (spec concepts absent
/// from implementation).
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
  let spec_paths = expand_spec_patterns(config.spec_patterns)
  let spec_files = collect_spec_files(spec_paths, registry)
  if spec_files.length() == 0 {
    return empty_report(config, [], [])
  }
  let kgf_ignore = registry.collect_ignore_patterns()
  let effective_root = match config.root_dir {
    Some(dir) => dir
    None => config.target_dir
  }
  let discover_opts = @pipeline.DiscoverOptions::new(
    kgf_ignore~,
    root_dir=effective_root,
  )
  let impl_files = collect_impl_files(
    config.target_dir,
    discover_opts,
    registry,
  )
  let spec_tokens = tokenize_file_set(spec_files, registry)
  let impl_tokens = tokenize_file_set(impl_files, registry)
  if spec_tokens.length() == 0 {
    return empty_report(
      config,
      spec_files.map(fn(file) { file.path }),
      impl_files.map(fn(file) { file.path }),
    )
  }
  let result = @vocab.measure_divergence(spec_tokens, impl_tokens, {
    ..@vocab.GapConfig::default(),
    max_terms: config.max_candidates,
  })
  let filtered_gaps = apply_focus(result.gap_terms, config.focus)
  let items = gap_terms_to_items(filtered_gaps)
  let summary = build_summary(items, result.cosine_distance)
  let used_specs = collect_used_specs(spec_files, impl_files)
  {
    version: "spec-verify-v1",
    generated_at: 0,
    config: {
      spec_paths: spec_files.map(fn(file) { file.path }),
      target_dir: config.target_dir,
      focus: config.focus,
      max_candidates: config.max_candidates,
    },
    summary: {
      ..summary,
      spec_files: spec_files.length(),
      impl_files: impl_files.length(),
      spec_symbols: spec_tokens.flatten().length(),
    },
    items,
    used_specs,
  }
}

///|
fn collect_spec_files(
  paths : Array[String],
  registry : @registry.KGFRegistry,
) -> Array[@pipeline.SupportedFile] {
  let result : Array[@pipeline.SupportedFile] = []
  for file in @pipeline.load_supported_file_info(paths, registry) {
    if file.content_type == Some("document") {
      result.push(file)
    }
  }
  result
}

///|
fn collect_impl_files(
  target_dir : String,
  options : @pipeline.DiscoverOptions,
  registry : @registry.KGFRegistry,
) -> Array[@pipeline.SupportedFile] {
  let result : Array[@pipeline.SupportedFile] = []
  for
    file in @pipeline.collect_supported_file_info(
      [target_dir],
      options,
      registry,
    ) {
    if file.content_type is None {
      result.push(file)
    }
  }
  result
}

///|
/// Tokenize a set of files individually, returning one token array per file.
fn tokenize_file_set(
  files : Array[@pipeline.SupportedFile],
  registry : @registry.KGFRegistry,
) -> Array[Array[String]] {
  let result : Array[Array[String]] = []
  for file in files {
    let tokens = @kgf_tokenize.tokenize_file(file.content, file.path, registry)
    if tokens.length() > 0 {
      result.push(tokens)
    }
  }
  result
}

///|
/// Apply focus filter to gap terms.
fn apply_focus(
  gaps : Array[@vocab.GapTerm],
  focus : String,
) -> Array[@vocab.GapTerm] {
  if focus == "all" {
    return gaps
  }
  gaps.filter(fn(g) { g.kind == focus })
}

///|
/// Convert gap terms to VerifyItems for the report.
fn gap_terms_to_items(gaps : Array[@vocab.GapTerm]) -> Array[VerifyItem] {
  gaps.map(fn(g) {
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
  })
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
fn build_summary(
  items : Array[VerifyItem],
  cosine_dist : Double,
) -> VerifySummary {
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
fn expand_spec_patterns(patterns : Array[String]) -> Array[String] {
  let result : Array[String] = []
  let seen : Map[String, Bool] = {}
  for pattern in patterns {
    let paths = @glob.expand_glob(pattern)
    for path in paths {
      if !seen.contains(path) {
        seen[path] = true
        result.push(path)
      }
    }
  }
  result
}

///|
fn collect_used_specs(
  spec_files : Array[@pipeline.SupportedFile],
  impl_files : Array[@pipeline.SupportedFile],
) -> Array[String] {
  let seen : Map[String, Bool] = {}
  let result : Array[String] = []
  let all_files = spec_files + impl_files
  for file in all_files {
    if !seen.contains(file.language) {
      seen[file.language] = true
      result.push(file.language)
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
