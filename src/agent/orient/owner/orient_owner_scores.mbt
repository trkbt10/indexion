///|
/// Score owner profiles against task terms using weighted lexical, focused
/// window, and BM25 summary similarity signals.
pub fn score_owner_briefs(
  orient_map : AgentOrientMap,
  task_terms : Array[String],
  task : String,
) -> Array[LocalOwnerBrief] {
  let result : Array[LocalOwnerBrief] = []
  let owner_doc_counts = build_owner_doc_counts(orient_map, task_terms)
  for owner in orient_map.owners {
    let owner_tokens = task_tokens(owner.summary)
    let dir = owner.path
    let summary = owner.summary
    let matched = matched_terms_in_tokens(task_terms, owner_tokens)
    result.push({
      path: dir,
      score: owner_orientation_score(
        task,
        summary,
        task_terms,
        matched,
        owner_doc_counts,
        orient_map.owners.length(),
      ),
      matched_terms: matched,
    })
  }
  result.sort_by(fn(a, b) {
    let c = b.score.compare(a.score)
    if c != 0 {
      c
    } else {
      a.path.compare(b.path)
    }
  })
  result
}

///|
pub fn owner_orientation_score(
  task : String,
  summary : String,
  task_terms : Array[String],
  matched : Array[String],
  owner_doc_counts : Map[String, Int],
  owner_count : Int,
) -> Double {
  let docs = [
    @tokenizer.tokenize_for_tfidf(task),
    @tokenizer.tokenize_for_tfidf(summary),
  ]
  let batch = @tfidf.BM25Batch::from_tokens(docs)
  let mut total = 0.0
  let mut hits = 0.0
  for term in task_terms {
    let weight = owner_term_weight(term, owner_doc_counts, owner_count)
    if weight <= 0.0 {
      continue
    }
    total += weight
    if matched.contains(term) {
      hits += weight
    }
  }
  let lexical = if total <= 0.0 { 0.0 } else { hits / total }
  let focus = focused_owner_window_score(
    summary, task_terms, owner_doc_counts, owner_count,
  )
  let score = lexical * 0.3 + focus * 0.35 + batch.similarity(0, 1) * 0.35
  if score > 1.0 {
    1.0
  } else {
    score
  }
}

///|
pub fn owner_term_weight(
  term : String,
  owner_doc_counts : Map[String, Int],
  owner_count : Int,
) -> Double {
  let docs = owner_doc_counts.get(term).unwrap_or(0)
  if docs == 0 {
    0.0
  } else {
    @math.ln((1.0 + owner_count.to_double()) / (1.0 + docs.to_double())) + 1.0
  }
}

///|
pub fn build_owner_doc_counts(
  orient_map : AgentOrientMap,
  task_terms : Array[String],
) -> Map[String, Int] {
  let counts : Map[String, Int] = Map([])
  for owner in orient_map.owners {
    let tokens = task_tokens(owner.summary)
    for term in task_terms {
      if tokens.contains(term) {
        counts[term] = counts.get(term).unwrap_or(0) + 1
      }
    }
  }
  counts
}
