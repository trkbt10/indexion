/// n:m BM25-based vocabulary divergence between source-side and prose-side.
///
/// Why BM25, not plain TF-IDF
/// ---------------------------
/// Earlier drafts of this module called `@vocab.measure_divergence`, which is
/// the engine `plan reconcile` uses for code↔documentation drift. That engine
/// applies a *hard* ubiquity filter — any term appearing in `total_docs / 3`
/// or more documents is dropped — which works well at code-corpus scale but
/// silently erases legitimate signals in small story corpora. A character
/// name that recurs across two prose chapters ("Parkinson") would land at
/// document-frequency 2 in a 5-document corpus and be filtered out of the
/// gap list entirely.
///
/// BM25 dissolves that problem at the weighting layer rather than via a
/// cutoff: its inverse-document-frequency term naturally suppresses
/// pervasive vocabulary while preserving rare-but-significant signals,
/// regardless of corpus size. We adopt BM25 here so the same module can
/// service short novella-scale fixtures and full-novel corpora without
/// retuning. (A future cleanup may push this back into reconcile so both
/// commands share one BM25-based engine.)
///
/// Three axes of analysis are produced per dataset:
///
/// 1. **Overall distance** — BM25 cosine distance between sources-as-document
///    and prose-as-document. A scalar drift indicator.
///
/// 2. **Per-chapter attribution** — for each prose chapter, BM25 cosine
///    similarity to each individual source document, plus aggregate similarity
///    to the union of sources.
///
/// 3. **Bidirectional gap terms** — under-coverage (terms BM25-significant in
///    sources but absent from prose; the writer hasn't picked them up) and
///    out-of-source drift (terms BM25-significant in prose but absent from
///    any source; introduced without grounding).

///|
/// Tokenize a single document via the KGF natural-language specs.
///
/// All language-specific knowledge — what counts as a word, what counts as a
/// particle/pronoun/auxiliary, what counts as punctuation — lives in the
/// `kgfs/natural/{language}.kgf` files, not in this code. The registry is
/// resolved at call time from the standard `kgfs/` location.
///
/// We then keep only the *content-bearing* feature kinds, declaratively
/// discarding function words and structural markers. Each KGF spec lists its
/// own POS tags; the kinds we keep below are the cross-language intersection
/// of "lexical content":
///
///   - English (`english.kgf`): Word, ProperNoun
///   - Japanese (`japanese.kgf`): Kanji, Katakana, Hiragana, Alnum
///   - Chinese (`chinese.kgf`): kanji-ideograph kinds
///   - Korean (`korean.kgf`): hangul kinds
///
/// Function words (Pronoun, Auxiliary, Article, Preposition, Conjunction,
/// Adverb, Negation, Question, Joshi, Punct, etc.) are dropped before they
/// enter the BM25 pipeline, which removes the need for the length-floor and
/// post-hoc demotion heuristics this module previously carried.
///
/// Public so the reconcile sub-module reuses the exact same tokenization
/// without reaching back into KGF independently.
pub fn tokenize_doc(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry,
) -> Array[String] {
  // Which kinds count as content is read from the KGF spec's
  // `identifier_kinds` declaration via `@identity` — no hard-coded
  // language list lives in this file. Adding a new natural-language
  // spec under `kgfs/story/` becomes a spec-only change.
  let kinds = @identity.identifier_kinds_for(registry, path)
  let raw = @kgf_tokenize.tokenize_file(content, path, registry)
  let result : Array[String] = []
  for feat in raw {
    if !@kgf_tokenize.feature_has_value(feat) {
      continue
    }
    let kind = @kgf_tokenize.feature_kind(feat)
    if !kinds.is_empty() && !kinds.contains(kind) {
      continue
    }
    let value = @kgf_tokenize.feature_value(feat)
    if value.length() == 0 {
      continue
    }
    // Emit just the value. Story divergence treats tokens as natural-
    // language words; the kind prefix is informative for filtering
    // but irrelevant for BM25/DF ranking and would clutter the gap-
    // term reports. Two kinds with the same surface form collapse to
    // one token, which is acceptable for prose where the writer sees
    // the literal word, not the language tag.
    result.push(value)
  }
  result
}

///|
/// Resolve the KGF registry for a story analysis run.
///
/// Story analysis uses a dedicated `kgfs/story/` registry that contains a
/// single multilingual-prose spec. This sidesteps the natural-language /
/// markdown / wiki specs all claiming `.md` simultaneously: when the user
/// runs `indexion story analyze`, only the prose spec is in scope.
///
/// We bypass `find_kgfs_dir`'s fall-back chain on purpose: that chain would
/// silently fall through to a general `kgfs/` directory if the story-scoped
/// one is missing, dragging in 80+ unrelated specs that all claim `.md` and
/// destroying our isolation. Instead we probe `<root>/kgfs/story/` and
/// `<CWD>/kgfs/story/` directly and load only the matching directory; if
/// neither exists we return an empty registry so the failure is loud.
fn load_story_registry(root : String) -> @kgf_registry.KGFRegistry {
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
/// Tokenize each document in the group via the story KGF registry. The
/// path is forwarded to KGF tokenize so the spec selection is consistent
/// with what the user would see by running `kgf tokens` on the same file.
fn tokens_for_group(
  docs : Array[StoryDocument],
  registry : @kgf_registry.KGFRegistry,
) -> Array[Array[String]] {
  let result : Array[Array[String]] = []
  for d in docs {
    result.push(tokenize_doc(d.content, d.path, registry))
  }
  result
}

///|
fn flatten(lists : Array[Array[String]]) -> Array[String] {
  let result : Array[String] = []
  for l in lists {
    for t in l {
      result.push(t)
    }
  }
  result
}

///|
/// Average length across non-empty token lists. Returns 1.0 as a safe floor
/// when the corpus is empty so BM25 division is well-defined.
fn average_length(lists : Array[Array[String]]) -> Double {
  let mut total = 0
  let mut count = 0
  for l in lists {
    if l.length() > 0 {
      total += l.length()
      count += 1
    }
  }
  if count == 0 {
    return 1.0
  }
  total.to_double() / count.to_double()
}

///|
/// Compute the n:m story divergence report between a spec group and an
/// impl group using BM25 weighting.
pub fn analyze_story(
  groups : StoryGroups,
  config : StoryConfig,
) -> StoryReport {
  let spec = groups.get_spec()
  let impl_ = groups.get_impl()
  let registry = load_story_registry(config.get_registry_root())
  let spec_tokens = tokens_for_group(spec, registry)
  let impl_tokens = tokens_for_group(impl_, registry)

  // 1. Overall distance: BM25 cosine between spec-union and impl-union,
  //    treating each side as a single document in a 2-doc corpus.
  let overall_distance = bm25_pair_distance(
    flatten(spec_tokens),
    flatten(impl_tokens),
  )

  // 2. Per-impl attribution.
  //    Build a single BM25 batch over [all spec..., all impl...] so DF and
  //    average length come from the entire corpus. Then read off similarity
  //    between each impl index and each spec index.
  let combined_tokens : Array[Array[String]] = []
  for t in spec_tokens {
    combined_tokens.push(t)
  }
  for t in impl_tokens {
    combined_tokens.push(t)
  }
  let batch = if combined_tokens.length() > 0 {
    @tfidf.BM25Batch::from_tokens(combined_tokens)
  } else {
    @tfidf.BM25Batch::from_tokens([[]])
  }
  let attributions : Array[ChapterAttribution] = []
  let n_spec = spec.length()
  for i, p in impl_ {
    let impl_idx = n_spec + i
    let by_spec : Array[PairSimilarity] = []
    for j, s in spec {
      let sim = if combined_tokens.length() > 0 {
        clamp_sim(batch.similarity(impl_idx, j))
      } else {
        0.0
      }
      by_spec.push({
        spec_path: s.path,
        impl_path: p.path,
        similarity: sim,
      })
    }
    by_spec.sort_by(fn(a, b) { b.similarity.compare(a.similarity) })
    let combined = bm25_pair_similarity(
      flatten(spec_tokens),
      impl_tokens[i],
    )
    attributions.push({
      impl_path: p.path,
      by_spec,
      combined_similarity: combined,
    })
  }

  // 3. Bidirectional gap terms via BM25 weighting.
  let under_coverage = compute_under_coverage(
    spec_tokens, impl_tokens, spec, config,
  )
  let out_of_source = compute_out_of_source(
    spec_tokens, impl_tokens, impl_, config,
  )
  {
    spec_count: spec.length(),
    impl_count: impl_.length(),
    overall_distance,
    attributions,
    under_coverage,
    out_of_source,
  }
}

///|
fn clamp_sim(v : Double) -> Double {
  if v < 0.0 {
    0.0
  } else if v > 1.0 {
    1.0
  } else {
    v
  }
}

///|
/// BM25 cosine similarity between two raw token arrays, treated as a 2-doc
/// corpus. Used for pair similarity outside the all-pairs batch.
/// Public so reconcile can score plot-act ↔ chapter pairs with the same
/// formula `analyze_story` uses.
pub fn bm25_pair_similarity(
  a_tokens : Array[String],
  b_tokens : Array[String],
) -> Double {
  if a_tokens.is_empty() || b_tokens.is_empty() {
    return 0.0
  }
  let docs = [a_tokens, b_tokens]
  let batch = @tfidf.BM25Batch::from_tokens(docs)
  clamp_sim(batch.similarity(0, 1))
}

///|
fn bm25_pair_distance(
  a_tokens : Array[String],
  b_tokens : Array[String],
) -> Double {
  let sim = bm25_pair_similarity(a_tokens, b_tokens)
  let d = 1.0 - sim
  if d < 0.0 {
    0.0
  } else if d > 1.0 {
    1.0
  } else {
    d
  }
}

///|
/// Compute under-coverage: terms with BM25 weight in the sources-as-document
/// that do not appear in the prose-as-document.
///
/// We build BM25 weights for the *sources* side using the full dataset's
/// document-frequency and average-length statistics, then walk the resulting
/// vector to keep only tokens absent from prose entirely. The DF-aware
/// weighting ensures common-everywhere words don't crowd out story-specific
/// signals — without needing a hard ubiquity cutoff.
fn compute_under_coverage(
  spec_tokens : Array[Array[String]],
  impl_tokens : Array[Array[String]],
  spec : Array[StoryDocument],
  config : StoryConfig,
) -> Array[UnderCoverageTerm] {
  let combined : Array[Array[String]] = []
  for t in spec_tokens {
    combined.push(t)
  }
  for t in impl_tokens {
    combined.push(t)
  }
  let df = @tfidf.build_document_frequency(combined)
  let avg_len = average_length(combined)
  let total = combined.length()
  let spec_flat = flatten(spec_tokens)
  let impl_set = build_token_set(impl_tokens)
  let vec = @tfidf.build_bm25_vector(spec_flat, df, total, avg_len)

  // Pre-compute per-document token presence so we can attribute origins.
  let spec_doc_tokens : Array[Map[String, Bool]] = []
  for tokens in spec_tokens {
    let s : Map[String, Bool] = {}
    for t in tokens {
      s[t] = true
    }
    spec_doc_tokens.push(s)
  }

  let candidates : Array[UnderCoverageTerm] = []
  for entry in vec.iter() {
    let term = entry.0
    let weight = entry.1
    if term.length() < config.min_value_length {
      continue
    }
    if impl_set.contains(term) {
      continue
    }
    if is_numeric(term) {
      continue
    }
    let origins : Array[String] = []
    for k, doc in spec_doc_tokens {
      if doc.contains(term) {
        origins.push(spec[k].path)
      }
    }
    candidates.push({ value: term, weight, origin_paths: origins })
  }
  // Sort with a soft penalty for terms that span every spec document.
  // BM25 already discounts ubiquity, but in small corpora a word that appears
  // in every doc on one side and zero on the other can still outweigh a
  // story-specific signal. The penalty preserves these terms in the output
  // (they may still be diagnostic) while letting concept-bearing gaps rise
  // above them.
  let total_spec = spec.length()
  candidates.sort_by(fn(a, b) {
    let aw = penalize(a.weight, a.origin_paths.length(), total_spec)
    let bw = penalize(b.weight, b.origin_paths.length(), total_spec)
    bw.compare(aw)
  })
  apply_term_limit_under(candidates, config.max_terms)
}

///|
/// Symmetric out-of-source: BM25 weights for the prose side, kept only for
/// tokens missing from sources entirely.
fn compute_out_of_source(
  spec_tokens : Array[Array[String]],
  impl_tokens : Array[Array[String]],
  impl_ : Array[StoryDocument],
  config : StoryConfig,
) -> Array[OutOfSourceTerm] {
  let combined : Array[Array[String]] = []
  for t in spec_tokens {
    combined.push(t)
  }
  for t in impl_tokens {
    combined.push(t)
  }
  let df = @tfidf.build_document_frequency(combined)
  let avg_len = average_length(combined)
  let total = combined.length()
  let impl_flat = flatten(impl_tokens)
  let spec_set = build_token_set(spec_tokens)
  let vec = @tfidf.build_bm25_vector(impl_flat, df, total, avg_len)

  let impl_doc_tokens : Array[Map[String, Bool]] = []
  for tokens in impl_tokens {
    let s : Map[String, Bool] = {}
    for t in tokens {
      s[t] = true
    }
    impl_doc_tokens.push(s)
  }

  let candidates : Array[OutOfSourceTerm] = []
  for entry in vec.iter() {
    let term = entry.0
    let weight = entry.1
    if term.length() < config.min_value_length {
      continue
    }
    if spec_set.contains(term) {
      continue
    }
    if is_numeric(term) {
      continue
    }
    let origins : Array[String] = []
    for k, doc in impl_doc_tokens {
      if doc.contains(term) {
        origins.push(impl_[k].path)
      }
    }
    candidates.push({ value: term, weight, origin_paths: origins })
  }
  let total_impl = impl_.length()
  candidates.sort_by(fn(a, b) {
    let aw = penalize(a.weight, a.origin_paths.length(), total_impl)
    let bw = penalize(b.weight, b.origin_paths.length(), total_impl)
    bw.compare(aw)
  })
  apply_term_limit_out(candidates, config.max_terms)
}

///|
/// Soft penalty for terms whose origin set spans every document on their
/// side. These are usually stylistic markers — function words, dialogue
/// tags, orthographic conventions — rather than story-specific signals.
/// We keep them in the output but discount their weight.
///
/// The heuristic only applies when the corpus has ≥ 3 documents on the
/// affected side: with one or two documents the "every document" condition
/// is too easy to meet, and a recurring story-specific motif (a name, a
/// repeated object) would be misclassified as a stylistic marker. Past
/// three documents the signal becomes statistically meaningful.
fn penalize(weight : Double, origin_count : Int, total : Int) -> Double {
  if total >= 3 && origin_count >= total {
    weight * 0.5
  } else {
    weight
  }
}

///|
fn build_token_set(lists : Array[Array[String]]) -> Map[String, Bool] {
  let s : Map[String, Bool] = {}
  for l in lists {
    for t in l {
      s[t] = true
    }
  }
  s
}

///|
fn is_numeric(value : String) -> Bool {
  if value.length() == 0 {
    return true
  }
  for c in value {
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
fn apply_term_limit_under(
  arr : Array[UnderCoverageTerm],
  max : Int,
) -> Array[UnderCoverageTerm] {
  if max <= 0 || arr.length() <= max {
    return arr
  }
  let result : Array[UnderCoverageTerm] = []
  for i = 0; i < max; i = i + 1 {
    result.push(arr[i])
  }
  result
}

///|
fn apply_term_limit_out(
  arr : Array[OutOfSourceTerm],
  max : Int,
) -> Array[OutOfSourceTerm] {
  if max <= 0 || arr.length() <= max {
    return arr
  }
  let result : Array[OutOfSourceTerm] = []
  for i = 0; i < max; i = i + 1 {
    result.push(arr[i])
  }
  result
}
