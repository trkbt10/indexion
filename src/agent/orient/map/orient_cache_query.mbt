///|
pub(all) struct OrientQueryCandidate {
  path : String
  role : String
  owner : String
  score : Double
  summary_preview : String
}

///|
pub(all) struct OrientDocumentationCandidate {
  path : String
  role : String
  owner : String
  score : Double
  summary_preview : String
  summary_full : String?
}

///|
pub(all) struct OrientOwnerCandidate {
  path : String
  score : Double
  implementation_paths : Array[String]
  top_implementation_path : String
  summary_preview : String
}

///|
pub(all) struct OrientEvidenceCandidate {
  path : String
  role : String
  score : Double
  summary : String
}

///|
pub(all) struct OrientQueryResult {
  task : String
  query_dim : Int
  owner_candidates : Array[OrientOwnerCandidate]
  implementation_hits : Array[OrientQueryCandidate]
  consumer_candidates : Array[OrientQueryCandidate]
  cli_consumers : Array[OrientQueryCandidate]
  documentation_sources : Array[OrientDocumentationCandidate]
  forbidden_surfaces : Array[OrientQueryCandidate]
  preflight_candidates : Array[OrientQueryCandidate]
  evidence_candidates : Array[OrientEvidenceCandidate]
}

///|
let orient_query_default_limit : Int = 12

///|
let orient_query_candidate_preview_limit : Int = orient_summary_preview_limit

///|
let orient_query_evidence_preview_limit : Int = 220

///|
pub fn query_orient_cache(
  handle : OrientCacheHandle,
  task : String,
  limit : Int,
) -> OrientQueryResult raise OrientCacheError {
  let query = handle.provider().embed(task)
  let query_limit = orient_query_limit(limit)
  let implementation_hits = orient_query_candidates_for_role(
    handle, query, "implementation", query_limit,
  )
  let consumer_candidates = orient_query_candidates_for_role(
    handle, query, "consumer", query_limit,
  )
  let cli_consumers = orient_query_candidates_for_role(
    handle, query, "cli-consumer", query_limit,
  )
  let documentation_sources = orient_documentation_candidates_for_role(
    handle, query, query_limit,
  )
  let owner_candidates = orient_owner_candidates_from_implementation_hits(
    implementation_hits, query_limit,
  )
  let forbidden_surfaces = copy_orient_query_candidates(cli_consumers)
  {
    task,
    query_dim: query.length(),
    owner_candidates,
    implementation_hits,
    consumer_candidates,
    cli_consumers,
    documentation_sources,
    forbidden_surfaces,
    preflight_candidates: orient_preflight_candidates(
      implementation_hits, documentation_sources, query_limit,
    ),
    evidence_candidates: orient_evidence_candidates(
      implementation_hits, consumer_candidates, cli_consumers, documentation_sources,
      query_limit,
    ),
  }
}

///|
fn orient_query_candidates_for_role(
  handle : OrientCacheHandle,
  query : Array[Double],
  role : String,
  limit : Int,
) -> Array[OrientQueryCandidate] raise OrientCacheError {
  let hits = handle.search(
    query,
    limit,
    filter=Some(orient_query_role_filter(role)),
  )
  let result : Array[OrientQueryCandidate] = []
  for hit in hits {
    result.push(orient_query_candidate_from_hit(hit))
  }
  result
}

///|
fn orient_documentation_candidates_for_role(
  handle : OrientCacheHandle,
  query : Array[Double],
  limit : Int,
) -> Array[OrientDocumentationCandidate] raise OrientCacheError {
  let hits = handle.search(
    query,
    limit,
    filter=Some(orient_query_role_filter("documentation")),
  )
  let result : Array[OrientDocumentationCandidate] = []
  for hit in hits {
    result.push(orient_documentation_candidate_from_hit(hit))
  }
  result
}

///|
fn orient_query_role_filter(role : String) -> @vcdb_filter.FilterExpr {
  @vcdb_filter.FilterExpr::match_("role", @vcdb_types.AttrValue::String(role))
}

///|
fn orient_query_candidate_from_hit(
  hit : OrientCacheSearchHit,
) -> OrientQueryCandidate {
  {
    path: hit.file.path,
    role: hit.file.role,
    owner: hit.file.owner,
    score: hit.score,
    summary_preview: orient_query_bounded_text(
      hit.file.summary_preview,
      orient_query_candidate_preview_limit,
    ),
  }
}

///|
fn orient_documentation_candidate_from_hit(
  hit : OrientCacheSearchHit,
) -> OrientDocumentationCandidate {
  {
    path: hit.file.path,
    role: hit.file.role,
    owner: hit.file.owner,
    score: hit.score,
    summary_preview: orient_query_bounded_text(
      hit.file.summary_preview,
      orient_query_candidate_preview_limit,
    ),
    summary_full: hit.file.summary_full,
  }
}

///|
fn orient_owner_candidates_from_implementation_hits(
  hits : Array[OrientQueryCandidate],
  limit : Int,
) -> Array[OrientOwnerCandidate] {
  let result : Array[OrientOwnerCandidate] = []
  for hit in hits {
    if hit.owner.length() == 0 {
      continue
    }
    match orient_owner_candidate_index(result, hit.owner) {
      Some(index) => {
        let candidate = result[index]
        if !candidate.implementation_paths.contains(hit.path) {
          candidate.implementation_paths.push(hit.path)
        }
        result[index] = { ..candidate, score: candidate.score + hit.score }
      }
      None =>
        result.push({
          path: hit.owner,
          score: hit.score,
          implementation_paths: [hit.path],
          top_implementation_path: hit.path,
          summary_preview: hit.summary_preview,
        })
    }
  }
  result.sort_by(fn(a, b) {
    let score_cmp = b.score.compare(a.score)
    if score_cmp != 0 {
      score_cmp
    } else {
      a.path.compare(b.path)
    }
  })
  orient_owner_candidates_prefix(result, limit)
}

///|
fn orient_owner_candidate_index(
  candidates : Array[OrientOwnerCandidate],
  path : String,
) -> Int? {
  for i in 0..<candidates.length() {
    if candidates[i].path == path {
      return Some(i)
    }
  }
  None
}

///|
fn orient_preflight_candidates(
  implementation_hits : Array[OrientQueryCandidate],
  documentation_sources : Array[OrientDocumentationCandidate],
  limit : Int,
) -> Array[OrientQueryCandidate] {
  let result : Array[OrientQueryCandidate] = []
  for candidate in implementation_hits {
    push_unique_orient_query_candidate(result, candidate)
    if result.length() >= limit {
      return result
    }
  }
  for doc in documentation_sources {
    push_unique_orient_query_candidate(
      result,
      orient_query_candidate_from_documentation(doc),
    )
    if result.length() >= limit {
      return result
    }
  }
  result
}

///|
fn orient_evidence_candidates(
  implementation_hits : Array[OrientQueryCandidate],
  consumer_candidates : Array[OrientQueryCandidate],
  cli_consumers : Array[OrientQueryCandidate],
  documentation_sources : Array[OrientDocumentationCandidate],
  limit : Int,
) -> Array[OrientEvidenceCandidate] {
  let result : Array[OrientEvidenceCandidate] = []
  for candidate in implementation_hits {
    push_unique_orient_evidence_candidate(
      result,
      orient_evidence_candidate_from_query(candidate),
    )
  }
  for candidate in consumer_candidates {
    push_unique_orient_evidence_candidate(
      result,
      orient_evidence_candidate_from_query(candidate),
    )
  }
  for candidate in cli_consumers {
    push_unique_orient_evidence_candidate(
      result,
      orient_evidence_candidate_from_query(candidate),
    )
  }
  for doc in documentation_sources {
    push_unique_orient_evidence_candidate(
      result,
      orient_evidence_candidate_from_query(
        orient_query_candidate_from_documentation(doc),
      ),
    )
  }
  result.sort_by(fn(a, b) {
    let score_cmp = b.score.compare(a.score)
    if score_cmp != 0 {
      score_cmp
    } else {
      a.path.compare(b.path)
    }
  })
  orient_evidence_candidates_prefix(result, limit)
}

///|
fn orient_query_candidate_from_documentation(
  doc : OrientDocumentationCandidate,
) -> OrientQueryCandidate {
  {
    path: doc.path,
    role: doc.role,
    owner: doc.owner,
    score: doc.score,
    summary_preview: doc.summary_preview,
  }
}

///|
fn orient_evidence_candidate_from_query(
  candidate : OrientQueryCandidate,
) -> OrientEvidenceCandidate {
  {
    path: candidate.path,
    role: candidate.role,
    score: candidate.score,
    summary: orient_query_evidence_preview(candidate.summary_preview),
  }
}

///|
fn push_unique_orient_query_candidate(
  result : Array[OrientQueryCandidate],
  candidate : OrientQueryCandidate,
) -> Unit {
  for existing in result {
    if existing.path == candidate.path {
      return
    }
  }
  result.push(candidate)
}

///|
fn push_unique_orient_evidence_candidate(
  result : Array[OrientEvidenceCandidate],
  candidate : OrientEvidenceCandidate,
) -> Unit {
  for existing in result {
    if existing.path == candidate.path {
      return
    }
  }
  result.push(candidate)
}

///|
fn copy_orient_query_candidates(
  candidates : Array[OrientQueryCandidate],
) -> Array[OrientQueryCandidate] {
  let result : Array[OrientQueryCandidate] = []
  for candidate in candidates {
    result.push(candidate)
  }
  result
}

///|
fn orient_owner_candidates_prefix(
  candidates : Array[OrientOwnerCandidate],
  limit : Int,
) -> Array[OrientOwnerCandidate] {
  let result : Array[OrientOwnerCandidate] = []
  let capped = orient_query_bounded_count(limit, candidates.length())
  for i in 0..<capped {
    result.push(candidates[i])
  }
  result
}

///|
fn orient_evidence_candidates_prefix(
  candidates : Array[OrientEvidenceCandidate],
  limit : Int,
) -> Array[OrientEvidenceCandidate] {
  let result : Array[OrientEvidenceCandidate] = []
  let capped = orient_query_bounded_count(limit, candidates.length())
  for i in 0..<capped {
    result.push(candidates[i])
  }
  result
}

///|
fn orient_query_limit(limit : Int) -> Int {
  if limit <= 0 {
    orient_query_default_limit
  } else {
    limit
  }
}

///|
fn orient_query_bounded_count(limit : Int, length : Int) -> Int {
  if limit <= 0 || limit > length {
    length
  } else {
    limit
  }
}

///|
fn orient_query_bounded_text(text : String, max_len : Int) -> String {
  if max_len <= 0 {
    ""
  } else if text.length() <= max_len {
    text
  } else {
    @config_paths.substring(text, 0, max_len)
  }
}

///|
fn orient_query_evidence_preview(text : String) -> String {
  if text.length() <= orient_query_evidence_preview_limit {
    text
  } else {
    @config_paths.substring(text, 0, orient_query_evidence_preview_limit) +
    "..."
  }
}
