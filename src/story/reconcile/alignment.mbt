/// Spec-act ↔ impl-doc alignment and drift action recommendation.
///
/// Given the acts extracted by `act_extractor` and the impl documents
/// passed in `StoryGroups.impl_`, this module:
///
/// 1. Scores every (act, impl) pair by BM25 cosine similarity, using the
///    same tokenization the divergence engine uses.
/// 2. Picks each act's best impl and any runner-ups within a small margin.
/// 3. Computes term-level missing/extra signals between an act and its
///    best impl — the building blocks of the writer-facing rationale.
/// 4. Decides a `DriftAction` per act based on a small set of explicit
///    rules.
///
/// The rules are intentionally simple and named so a writer can reason
/// about them. We do not invoke any LLM here: the recommendation surface
/// is a deterministic function of similarity scores, term sets, and the
/// configured floors. An agent layer above this can narrate the rationale.

///|
/// Build a reconcile report from a loaded `StoryGroups`.
pub fn reconcile(
  groups : @story.StoryGroups,
  config : ReconcileConfig,
) -> ReconcileReport {
  let registry = resolve_registry(config.get_registry_root())
  let acts = extract_acts(groups, registry)
  let impl_ = groups.get_impl()
  let impl_paths : Array[String] = []
  for p in impl_ {
    impl_paths.push(p.get_path())
  }
  let candidates = build_candidates(acts, impl_, config, registry)
  let orphan_impl = compute_orphans(impl_paths, candidates)
  {
    acts,
    impl_paths,
    candidates,
    orphan_impl,
  }
}

///|
fn build_candidates(
  acts : Array[PlotAct],
  impl_ : Array[@story.StoryDocument],
  config : ReconcileConfig,
  registry : @kgf_registry.KGFRegistry,
) -> Array[ActReconcileCandidate] {
  // Pre-compute corpus-wide statistics so that BM25 weights inside
  // `compute_term_diffs` reflect each term's discriminative value across
  // the whole story rather than the trivial 2-document act+impl pair.
  let corpus_tokens : Array[Array[String]] = []
  for a in acts {
    corpus_tokens.push(@story.tokenize_doc(a.body, a.source_path, registry))
  }
  for p in impl_ {
    corpus_tokens.push(
      @story.tokenize_doc(p.get_content(), p.get_path(), registry),
    )
  }
  let corpus_df = @tfidf.build_document_frequency(corpus_tokens)
  let corpus_avg_len = corpus_average_length(corpus_tokens)
  let corpus_total = corpus_tokens.length()
  let result : Array[ActReconcileCandidate] = []
  for act in acts {
    result.push(
      build_candidate(
        act, impl_, config, registry, corpus_df, corpus_total, corpus_avg_len,
      ),
    )
  }
  result
}

///|
/// Resolve the KGF registry for reconcile. Mirrors `load_story_registry`
/// in src/story/divergence.mbt: probe `<root>/kgfs/story/` and
/// `<CWD>/kgfs/story/` directly without falling through to a general
/// kgfs/ directory.
fn resolve_registry(root : String) -> @kgf_registry.KGFRegistry {
  let root_dir = if root.length() == 0 { "." } else { root }
  let candidates = [
    @config_paths.join_path(root_dir, "kgfs/story"),
    "kgfs/story",
  ]
  for path in candidates {
    if @fs.path_exists(path) {
      return @kgf_registry.KGFRegistry::load_from_dir(path)
    }
  }
  @kgf_registry.KGFRegistry::new()
}

///|
fn corpus_average_length(docs : Array[Array[String]]) -> Double {
  let mut total = 0
  let mut count = 0
  for d in docs {
    if d.length() > 0 {
      total += d.length()
      count += 1
    }
  }
  if count == 0 {
    1.0
  } else {
    total.to_double() / count.to_double()
  }
}

///|
fn build_candidate(
  act : PlotAct,
  impl_ : Array[@story.StoryDocument],
  config : ReconcileConfig,
  registry : @kgf_registry.KGFRegistry,
  corpus_df : Map[String, Int],
  corpus_total : Int,
  corpus_avg_len : Double,
) -> ActReconcileCandidate {
  let act_tokens = @story.tokenize_doc(act.body, act.source_path, registry)
  let pairs : Array[ImplMatch] = []
  for p in impl_ {
    let impl_tokens = @story.tokenize_doc(
      p.get_content(), p.get_path(), registry,
    )
    let sim = @story.bm25_pair_similarity(act_tokens, impl_tokens)
    pairs.push({ impl_path: p.get_path(), similarity: sim })
  }
  pairs.sort_by(fn(a, b) { b.similarity.compare(a.similarity) })
  let best_match : ImplMatch? = if pairs.length() > 0 &&
    pairs[0].similarity >= config.similarity_floor {
    Some(pairs[0])
  } else {
    None
  }
  let runner_ups : Array[ImplMatch] = []
  match best_match {
    Some(best) => {
      let cutoff = best.similarity - config.runner_up_margin
      for i = 1; i < pairs.length(); i = i + 1 {
        if pairs[i].similarity >= cutoff &&
          pairs[i].similarity >= config.similarity_floor {
          runner_ups.push(pairs[i])
        }
      }
    }
    None => ()
  }
  let (missing_terms, extra_terms, covered_terms) = compute_term_diffs(
    act, impl_, best_match, config.max_terms_per_candidate,
    registry, corpus_df, corpus_total, corpus_avg_len,
  )
  let action = decide_action(
    best_match, runner_ups, missing_terms.length(), extra_terms.length(),
  )
  let rationale = build_rationale(
    action, best_match, runner_ups, missing_terms, extra_terms,
  )
  {
    act,
    best_match,
    runner_ups,
    missing_terms,
    extra_terms,
    covered_terms,
    action,
    rationale,
  }
}

///|
/// Term-level diff between an act body and its best-match impl content.
/// Returns (missing, extra, covered) where:
///   - missing: tokens in act but absent from impl
///   - extra:   tokens in impl but absent from act
///   - covered: tokens in act AND in impl (BM25-weighted from the act
///              vector, parallel to `missing`). Surfaces the
///              intersection so callers running reconcile in inverted
///              polarity (spec corpus = constraints the impl must not
///              echo) can read leak terms directly from the report.
///
/// Ranked by BM25 weight against the full corpus so that frequent low-
/// information words (function words) sink. Function words are also
/// stripped upstream by KGF feature-kind filtering, so the result is
/// already mostly content tokens.
fn compute_term_diffs(
  act : PlotAct,
  impl_ : Array[@story.StoryDocument],
  best_match : ImplMatch?,
  max_terms : Int,
  registry : @kgf_registry.KGFRegistry,
  corpus_df : Map[String, Int],
  corpus_total : Int,
  corpus_avg_len : Double,
) -> (Array[String], Array[String], Array[String]) {
  let act_tokens = @story.tokenize_doc(act.body, act.source_path, registry)
  match best_match {
    None => ([], [], [])
    Some(m) => {
      let impl_content = lookup_impl_content(impl_, m.impl_path)
      let impl_tokens = @story.tokenize_doc(
        impl_content, m.impl_path, registry,
      )
      let impl_set = build_token_set(impl_tokens)
      let act_set = build_token_set(act_tokens)
      let missing_vec = @tfidf.build_bm25_vector(
        act_tokens, corpus_df, corpus_total, corpus_avg_len,
      )
      let extra_vec = @tfidf.build_bm25_vector(
        impl_tokens, corpus_df, corpus_total, corpus_avg_len,
      )
      let missing_candidates : Array[(String, Double)] = []
      let covered_candidates : Array[(String, Double)] = []
      for entry in missing_vec.iter() {
        let term = entry.0
        let weight = entry.1
        if is_numeric_value(term) {
          continue
        }
        if impl_set.contains(term) {
          covered_candidates.push((term, weight))
        } else {
          missing_candidates.push((term, weight))
        }
      }
      let extra_candidates : Array[(String, Double)] = []
      for entry in extra_vec.iter() {
        let term = entry.0
        let weight = entry.1
        if act_set.contains(term) {
          continue
        }
        if is_numeric_value(term) {
          continue
        }
        extra_candidates.push((term, weight))
      }
      missing_candidates.sort_by(fn(a, b) { b.1.compare(a.1) })
      extra_candidates.sort_by(fn(a, b) { b.1.compare(a.1) })
      covered_candidates.sort_by(fn(a, b) { b.1.compare(a.1) })
      let missing : Array[String] = []
      for i = 0; i < missing_candidates.length() && i < max_terms; i = i + 1 {
        missing.push(missing_candidates[i].0)
      }
      let extra : Array[String] = []
      for i = 0; i < extra_candidates.length() && i < max_terms; i = i + 1 {
        extra.push(extra_candidates[i].0)
      }
      let covered : Array[String] = []
      for i = 0; i < covered_candidates.length() && i < max_terms; i = i + 1 {
        covered.push(covered_candidates[i].0)
      }
      (missing, extra, covered)
    }
  }
}

///|
fn lookup_impl_content(
  impl_ : Array[@story.StoryDocument],
  path : String,
) -> String {
  for p in impl_ {
    if p.get_path() == path {
      return p.get_content()
    }
  }
  ""
}

///|
fn build_token_set(tokens : Array[String]) -> Map[String, Bool] {
  let s : Map[String, Bool] = {}
  for t in tokens {
    s[t] = true
  }
  s
}

///|
fn is_numeric_value(s : String) -> Bool {
  if s.length() == 0 {
    return true
  }
  for c in s {
    let code = c.to_int()
    let is_digit = code >= 0x30 && code <= 0x39
    let is_punct = c == '.' || c == ',' || c == '-' || c == '_'
    if !is_digit && !is_punct {
      return false
    }
  }
  true
}

///|
/// Decide a drift action based on best match, runner-ups, and the size
/// of the term-level diffs. Order of evaluation matters: `MissingFromImpl`
/// is the most severe verdict and is checked first.
fn decide_action(
  best_match : ImplMatch?,
  runner_ups : Array[ImplMatch],
  missing_count : Int,
  extra_count : Int,
) -> DriftAction {
  match best_match {
    None => MissingFromImpl
    Some(best) => {
      if runner_ups.length() >= 1 {
        return ConsolidateImpl
      }
      if best.similarity < 0.30 && missing_count >= 3 {
        return ExpandImpl
      }
      if best.similarity >= 0.30 && extra_count >= missing_count + 4 {
        return PruneStray
      }
      Ok
    }
  }
}

///|
/// Compose a one-line rationale describing why an action was chosen.
fn build_rationale(
  action : DriftAction,
  best_match : ImplMatch?,
  runner_ups : Array[ImplMatch],
  missing_terms : Array[String],
  extra_terms : Array[String],
) -> String {
  let buf = StringBuilder::new()
  buf.write_string(action.label())
  buf.write_string(": ")
  match action {
    Ok =>
      match best_match {
        Some(m) => {
          buf.write_string("best impl ")
          buf.write_string(m.impl_path)
          buf.write_string(" matches at ")
          buf.write_string(@text_format.format_percent(m.similarity))
        }
        None => buf.write_string("no signal")
      }
    ExpandImpl =>
      match best_match {
        Some(m) => {
          buf.write_string(m.impl_path)
          buf.write_string(" similarity ")
          buf.write_string(@text_format.format_percent(m.similarity))
          buf.write_string(", missing: ")
          buf.write_string(@text_ops.join_with_limit(missing_terms, 3))
        }
        None => buf.write_string("missing entirely")
      }
    ConsolidateImpl =>
      match best_match {
        Some(m) => {
          buf.write_string(m.impl_path)
          buf.write_string(" + ")
          buf.write_string(runner_ups.length().to_string())
          buf.write_string(" other impl doc(s) all score similarly")
        }
        None => buf.write_string("multiple weak matches")
      }
    PruneStray =>
      match best_match {
        Some(m) => {
          buf.write_string(m.impl_path)
          buf.write_string(" introduces unrelated terms: ")
          buf.write_string(@text_ops.join_with_limit(extra_terms, 3))
        }
        None => buf.write_string("stray content")
      }
    MissingFromImpl =>
      buf.write_string("no impl doc exceeds the similarity floor")
  }
  buf.to_string()
}

///|
/// Impl docs that are not the best match for any act — orphan candidates.
fn compute_orphans(
  impl_paths : Array[String],
  candidates : Array[ActReconcileCandidate],
) -> Array[String] {
  let claimed : Map[String, Bool] = {}
  for c in candidates {
    match c.best_match {
      Some(m) => claimed[m.impl_path] = true
      None => ()
    }
  }
  let orphans : Array[String] = []
  for path in impl_paths {
    if !claimed.contains(path) {
      orphans.push(path)
    }
  }
  orphans
}
