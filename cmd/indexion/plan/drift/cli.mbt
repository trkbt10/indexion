///|
/// `plan drift` — detect translation / documentation drift between two files
/// using `@vocab.measure_divergence` in natural-language mode.

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = DriftConfig::from_matches(matches)
  if config.file_a.length() == 0 || config.file_b.length() == 0 {
    println("Error: Two file paths required.")
    println("")
    println("Usage: indexion plan drift [options] <file_a> <file_b>")
    return
  }
  let report = match build_report(config) {
    Some(r) => r
    None => return
  }
  @common.write_output(
    config.output,
    render_output(report, config.format),
    label="Drift report",
  )
  match report.threshold_passed {
    Some(false) => @common.exit_with_code(1)
    _ => ()
  }
}

///|
/// Build a `DriftReport` from a config. Exposed for integration tests; the
/// CLI dispatch routes through `run_matches`.
pub fn build_report(config : DriftConfig) -> DriftReport? {
  let content_a = @fs.read_file_to_string(config.file_a) catch {
    _ => {
      println("Error: cannot read file: " + config.file_a)
      return None
    }
  }
  let content_b = @fs.read_file_to_string(config.file_b) catch {
    _ => {
      println("Error: cannot read file: " + config.file_b)
      return None
    }
  }
  let registry = match config.specs_dir {
    Some(dir) => @kgf_features.load_registry_or_empty(specs_dir=dir, target_dir=".")
    None => @kgf_features.load_registry_or_empty(target_dir=".")
  }
  if registry.get_languages().length() == 0 {
    println(
      "Error: no KGF specs were loaded. Run from a directory whose ancestry " +
      "contains a `kgfs/` directory, or pass --specs-dir.",
    )
    return None
  }
  let lang_a = registry.detect_from_path(config.file_a)
  let lang_b = registry.detect_from_path(config.file_b)
  let tokens_a = @kgf_tokenize.tokenize_file(content_a, config.file_a, registry)
  let tokens_b = @kgf_tokenize.tokenize_file(content_b, config.file_b, registry)
  if tokens_a.length() == 0 {
    println(
      "Error: no tokens extracted from " +
      config.file_a +
      describe_lang(lang_a, "no matching KGF spec"),
    )
    return None
  }
  if tokens_b.length() == 0 {
    println(
      "Error: no tokens extracted from " +
      config.file_b +
      describe_lang(lang_b, "no matching KGF spec"),
    )
    return None
  }
  let gap_config : @vocab.GapConfig = {
    min_value_length: 2,
    max_terms: config.top,
    include_vocab_terms: true,
  }
  let forward = @vocab.measure_divergence([tokens_a], [tokens_b], gap_config)
  let reverse = @vocab.measure_divergence([tokens_b], [tokens_a], gap_config)
  let cosine_distance = forward.cosine_distance
  let (threshold_passed, threshold) = match config.vocab_threshold {
    Some(t) => (Some(cosine_distance <= t), Some(t))
    None => (None, None)
  }
  Some({
    version: "drift-v1",
    file_a: config.file_a,
    file_b: config.file_b,
    spec_a: lang_or_unknown(lang_a),
    spec_b: lang_or_unknown(lang_b),
    feature_token_count_a: tokens_a.length(),
    feature_token_count_b: tokens_b.length(),
    cosine_distance,
    a_to_b: {
      source_path: config.file_a,
      target_path: config.file_b,
      gap_terms: forward.gap_terms.map(to_drift_term),
    },
    b_to_a: {
      source_path: config.file_b,
      target_path: config.file_a,
      gap_terms: reverse.gap_terms.map(to_drift_term),
    },
    threshold_passed,
    threshold,
  })
}

///|
fn to_drift_term(g : @vocab.GapTerm) -> DriftGapTerm {
  { value: g.value, kind: g.kind, weight: g.weight }
}

///|
fn describe_lang(lang : String?, fallback : String) -> String {
  match lang {
    Some(name) => " (KGF spec: " + name + ")"
    None => " (" + fallback + ")"
  }
}

///|
fn lang_or_unknown(lang : String?) -> String {
  match lang {
    Some(name) => name
    None => "unknown"
  }
}
