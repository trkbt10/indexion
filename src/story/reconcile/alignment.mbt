/// Plot-act ↔ prose-chapter alignment and drift action recommendation.
///
/// Given the acts extracted by `act_extractor` and the prose loaded by the
/// shared story loader, this module:
///
/// 1. Scores every (act, chapter) pair by BM25 cosine similarity, using the
///    same tokenization the divergence engine uses.
/// 2. Picks each act's best chapter and any runner-ups within a small margin.
/// 3. Computes term-level missing/extra signals between an act and its best
///    chapter — the building blocks of the writer-facing rationale.
/// 4. Decides a `DriftAction` per act based on a small set of explicit rules.
///
/// The rules are intentionally simple and named so a writer can reason about
/// them. We do not invoke any LLM here: the recommendation surface is a
/// deterministic function of similarity scores, term sets, and the configured
/// floors. An agent layer above this can then narrate the rationale.

///|
/// Build a reconcile report from a loaded story dataset.
pub fn reconcile(
  dataset : @story.StoryDataset,
  config : ReconcileConfig,
) -> ReconcileReport {
  let acts = extract_acts(dataset)
  let prose = dataset.get_prose()
  // Reconcile shares the story-scoped registry with `analyze_story` so the
  // two commands agree on tokenization. See `load_story_registry` in
  // src/story/divergence.mbt for the resolution rules; we mirror them here
  // because reconcile lives in a sub-package.
  let root = dataset.get_root()
  let registry = resolve_registry(root)
  let prose_paths : Array[String] = []
  for p in prose {
    prose_paths.push(p.get_rel_path())
  }
  let candidates = build_candidates(acts, prose, config, registry)
  let orphan_chapters = compute_orphans(prose_paths, candidates)
  {
    root: dataset.get_root(),
    acts,
    prose_paths,
    candidates,
    orphan_chapters,
  }
}

///|
fn build_candidates(
  acts : Array[PlotAct],
  prose : Array[@story.ProseDoc],
  config : ReconcileConfig,
  registry : @kgf_registry.KGFRegistry,
) -> Array[ActReconcileCandidate] {
  // Pre-compute corpus-wide statistics so that BM25 weights inside
  // `compute_term_diffs` reflect each term's discriminative value across the
  // entire story rather than the trivial 2-document act+chapter pair.
  let corpus_tokens : Array[Array[String]] = []
  for a in acts {
    corpus_tokens.push(@story.tokenize_doc(a.body, a.source_path, registry))
  }
  for p in prose {
    corpus_tokens.push(
      @story.tokenize_doc(p.get_content(), p.get_rel_path(), registry),
    )
  }
  let corpus_df = @tfidf.build_document_frequency(corpus_tokens)
  let corpus_avg_len = corpus_average_length(corpus_tokens)
  let corpus_total = corpus_tokens.length()
  let result : Array[ActReconcileCandidate] = []
  for act in acts {
    result.push(
      build_candidate(
        act, prose, config, registry, corpus_df, corpus_total, corpus_avg_len,
      ),
    )
  }
  result
}

///|
/// Resolve the KGF registry for reconcile. Mirrors `load_story_registry` in
/// src/story/divergence.mbt: probe `<root>/kgfs/story/` and `<CWD>/kgfs/story/`
/// directly without falling through to a general kgfs/ directory.
fn resolve_registry(root : String) -> @kgf_registry.KGFRegistry {
  let candidates = [
    @config_paths.join_path(root, "kgfs/story"),
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
  prose : Array[@story.ProseDoc],
  config : ReconcileConfig,
  registry : @kgf_registry.KGFRegistry,
  corpus_df : Map[String, Int],
  corpus_total : Int,
  corpus_avg_len : Double,
) -> ActReconcileCandidate {
  let act_tokens = @story.tokenize_doc(act.body, act.source_path, registry)
  let pairs : Array[ChapterMatch] = []
  for p in prose {
    let chapter_tokens = @story.tokenize_doc(
      p.get_content(), p.get_rel_path(), registry,
    )
    let sim = @story.bm25_pair_similarity(act_tokens, chapter_tokens)
    pairs.push({ prose_path: p.get_rel_path(), similarity: sim })
  }
  pairs.sort_by(fn(a, b) { b.similarity.compare(a.similarity) })
  let best_match : ChapterMatch? = if pairs.length() > 0 &&
    pairs[0].similarity >= config.similarity_floor {
    Some(pairs[0])
  } else {
    None
  }
  let runner_ups : Array[ChapterMatch] = []
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
  let (missing_terms, extra_terms) = compute_term_diffs(
    act, prose, best_match, config.max_terms_per_candidate,
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
    action,
    rationale,
  }
}

///|
/// Term-level diff between an act body and its best-match chapter content.
/// Returns (missing, extra) where:
///   - missing: tokens in act but absent from chapter (non-trivial length)
///   - extra:   tokens in chapter but absent from act
///
/// We rank candidates by BM25 weight against the act+chapter mini-corpus so
/// that frequent low-information words (function words) sink. This mirrors
/// how the divergence engine surfaces story-relevant signals over noise.
fn compute_term_diffs(
  act : PlotAct,
  prose : Array[@story.ProseDoc],
  best_match : ChapterMatch?,
  max_terms : Int,
  registry : @kgf_registry.KGFRegistry,
  corpus_df : Map[String, Int],
  corpus_total : Int,
  corpus_avg_len : Double,
) -> (Array[String], Array[String]) {
  let act_tokens = @story.tokenize_doc(act.body, act.source_path, registry)
  match best_match {
    None => ([], [])
    Some(m) => {
      let chapter_content = lookup_prose_content(prose, m.prose_path)
      let chapter_tokens = @story.tokenize_doc(
        chapter_content, m.prose_path, registry,
      )
      let chapter_set = build_token_set(chapter_tokens)
      let act_set = build_token_set(act_tokens)
      // Use corpus-wide DF so function words get suppressed by IDF.
      let missing_vec = @tfidf.build_bm25_vector(
        act_tokens, corpus_df, corpus_total, corpus_avg_len,
      )
      let extra_vec = @tfidf.build_bm25_vector(
        chapter_tokens, corpus_df, corpus_total, corpus_avg_len,
      )
      // Function words have already been stripped during KGF tokenization
      // (Pronoun, Auxiliary, Joshi, Punct, etc. are dropped by feature-kind
      // filtering in `@story.tokenize_doc`). What remains is content tokens
      // weighted by corpus-wide BM25, so we keep the missing/extra lists in
      // raw weight order without further demotion.
      let missing_candidates : Array[(String, Double)] = []
      for entry in missing_vec.iter() {
        let term = entry.0
        let weight = entry.1
        if chapter_set.contains(term) {
          continue
        }
        if is_numeric_value(term) {
          continue
        }
        missing_candidates.push((term, weight))
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
      let missing : Array[String] = []
      for i = 0; i < missing_candidates.length() && i < max_terms; i = i + 1 {
        missing.push(missing_candidates[i].0)
      }
      let extra : Array[String] = []
      for i = 0; i < extra_candidates.length() && i < max_terms; i = i + 1 {
        extra.push(extra_candidates[i].0)
      }
      (missing, extra)
    }
  }
}

///|
fn lookup_prose_content(
  prose : Array[@story.ProseDoc],
  rel_path : String,
) -> String {
  for p in prose {
    if p.get_rel_path() == rel_path {
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
/// Decide a drift action for an act based on its best match, runner-ups,
/// and the size of the term-level diffs. Order of evaluation matters:
/// `MissingFromProse` is the most severe verdict and is checked first.
fn decide_action(
  best_match : ChapterMatch?,
  runner_ups : Array[ChapterMatch],
  missing_count : Int,
  extra_count : Int,
) -> DriftAction {
  match best_match {
    None => MissingFromProse
    Some(best) => {
      // Multiple chapters within the runner-up margin → split or diluted act.
      if runner_ups.length() >= 1 {
        return ConsolidateChapters
      }
      // Best similarity is moderate but heavy missing terms → expand prose.
      if best.similarity < 0.30 && missing_count >= 3 {
        return ExpandProse
      }
      // High similarity but heavy extras → prose introduced unrelated material.
      if best.similarity >= 0.30 && extra_count >= missing_count + 4 {
        return PruneStrayScenes
      }
      Ok
    }
  }
}

///|
/// Compose a one-line rationale describing why a particular action was
/// chosen. The rationale references concrete numbers from the candidate so
/// a writer can verify the reasoning.
fn build_rationale(
  action : DriftAction,
  best_match : ChapterMatch?,
  runner_ups : Array[ChapterMatch],
  missing_terms : Array[String],
  extra_terms : Array[String],
) -> String {
  let buf = StringBuilder::new()
  buf.write_string(action.label())
  buf.write_string(": ")
  match action {
    Ok => {
      match best_match {
        Some(m) => {
          buf.write_string("best chapter ")
          buf.write_string(m.prose_path)
          buf.write_string(" matches at ")
          buf.write_string(format_similarity_pct(m.similarity))
        }
        None => buf.write_string("no signal")
      }
    }
    ExpandProse => {
      match best_match {
        Some(m) => {
          buf.write_string(m.prose_path)
          buf.write_string(" similarity ")
          buf.write_string(format_similarity_pct(m.similarity))
          buf.write_string(", missing: ")
          buf.write_string(join_first(missing_terms, 3))
        }
        None => buf.write_string("missing entirely")
      }
    }
    ConsolidateChapters => {
      match best_match {
        Some(m) => {
          buf.write_string(m.prose_path)
          buf.write_string(" + ")
          buf.write_string(runner_ups.length().to_string())
          buf.write_string(" other chapter(s) all score similarly")
        }
        None => buf.write_string("multiple weak matches")
      }
    }
    PruneStrayScenes => {
      match best_match {
        Some(m) => {
          buf.write_string(m.prose_path)
          buf.write_string(" introduces unrelated terms: ")
          buf.write_string(join_first(extra_terms, 3))
        }
        None => buf.write_string("stray content")
      }
    }
    MissingFromProse =>
      buf.write_string("no chapter exceeds the similarity floor")
  }
  buf.to_string()
}

///|
fn format_similarity_pct(v : Double) -> String {
  let pct = (v * 100.0 + 0.5).to_int()
  pct.to_string() + "%"
}

///|
fn join_first(arr : Array[String], n : Int) -> String {
  let buf = StringBuilder::new()
  let limit = if n < arr.length() { n } else { arr.length() }
  for i = 0; i < limit; i = i + 1 {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(arr[i])
  }
  if arr.length() > limit {
    buf.write_string(" (+")
    buf.write_string((arr.length() - limit).to_string())
    buf.write_string(" more)")
  }
  buf.to_string()
}

///|
/// Chapters that are not the best match for any act. They are candidates
/// for "remove" or "this scene has no plot anchor" follow-up work.
fn compute_orphans(
  prose_paths : Array[String],
  candidates : Array[ActReconcileCandidate],
) -> Array[String] {
  let claimed : Map[String, Bool] = {}
  for c in candidates {
    match c.best_match {
      Some(m) => claimed[m.prose_path] = true
      None => ()
    }
  }
  let orphans : Array[String] = []
  for path in prose_paths {
    if !claimed.contains(path) {
      orphans.push(path)
    }
  }
  orphans
}
