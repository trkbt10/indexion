///|
pub(all) struct QueryCandidate {
  path : String
  role : String
  owner : String
  score : Double
  summary_preview : String
}

///|
pub(all) struct DocumentationCandidate {
  path : String
  role : String
  owner : String
  score : Double
  summary_preview : String
  summary_full : String?
}

///|
pub(all) struct OwnerCandidate {
  path : String
  score : Double
  implementation_paths : Array[String]
  top_implementation_path : String
  summary_preview : String
}

///|
pub(all) struct EvidenceCandidate {
  path : String
  role : String
  score : Double
  summary : String
}

///|
pub(all) struct QueryResult {
  task : String
  query_dim : Int
  owner_candidates : Array[OwnerCandidate]
  implementation_hits : Array[QueryCandidate]
  consumer_candidates : Array[QueryCandidate]
  cli_consumers : Array[QueryCandidate]
  documentation_sources : Array[DocumentationCandidate]
  forbidden_surfaces : Array[QueryCandidate]
  preflight_candidates : Array[QueryCandidate]
  evidence_candidates : Array[EvidenceCandidate]
}

///|
let query_default_limit : Int = 12

///|
let query_candidate_preview_limit : Int = summary_preview_limit

///|
let query_evidence_preview_limit : Int = 220

///|
pub fn query(
  handle : Handle,
  task : String,
  limit : Int,
) -> QueryResult raise CacheError {
  let query = handle.provider().embed(task)
  let query_limit = query_limit_or_default(limit)
  let implementation_hits = query_candidates_for_role(
    handle, query, "implementation", query_limit,
  )
  let consumer_candidates = query_candidates_for_role(
    handle, query, "consumer", query_limit,
  )
  let cli_consumers = query_candidates_for_role(
    handle, query, "cli-consumer", query_limit,
  )
  let documentation_sources = documentation_candidates_for_role(
    handle, query, query_limit,
  )
  let owner_candidates = owner_candidates_from_implementation_hits(
    implementation_hits, query_limit,
  )
  let forbidden_surfaces = copy_query_candidates(cli_consumers)
  {
    task,
    query_dim: query.length(),
    owner_candidates,
    implementation_hits,
    consumer_candidates,
    cli_consumers,
    documentation_sources,
    forbidden_surfaces,
    preflight_candidates: preflight_candidates(
      implementation_hits, documentation_sources, query_limit,
    ),
    evidence_candidates: evidence_candidates(
      implementation_hits, consumer_candidates, cli_consumers, documentation_sources,
      query_limit,
    ),
  }
}

///|
fn query_candidates_for_role(
  handle : Handle,
  query : Array[Double],
  role : String,
  limit : Int,
) -> Array[QueryCandidate] raise CacheError {
  let hits = handle.search(query, limit, filter=Some(query_role_filter(role)))
  let result : Array[QueryCandidate] = []
  for hit in hits {
    result.push(query_candidate_from_hit(hit))
  }
  result
}

///|
fn documentation_candidates_for_role(
  handle : Handle,
  query : Array[Double],
  limit : Int,
) -> Array[DocumentationCandidate] raise CacheError {
  let hits = handle.search(
    query,
    limit,
    filter=Some(query_role_filter("documentation")),
  )
  let result : Array[DocumentationCandidate] = []
  for hit in hits {
    result.push(documentation_candidate_from_hit(hit))
  }
  result
}

///|
fn query_role_filter(role : String) -> @vcdb_filter.FilterExpr {
  @vcdb_filter.FilterExpr::match_("role", @vcdb_types.AttrValue::String(role))
}

///|
fn query_candidate_from_hit(hit : SearchHit) -> QueryCandidate {
  {
    path: hit.file.path,
    role: hit.file.role,
    owner: hit.file.owner,
    score: hit.score,
    summary_preview: bounded_text(
      hit.file.summary_preview,
      query_candidate_preview_limit,
    ),
  }
}

///|
fn documentation_candidate_from_hit(hit : SearchHit) -> DocumentationCandidate {
  {
    path: hit.file.path,
    role: hit.file.role,
    owner: hit.file.owner,
    score: hit.score,
    summary_preview: bounded_text(
      hit.file.summary_preview,
      query_candidate_preview_limit,
    ),
    summary_full: hit.file.summary_full,
  }
}

///|
fn owner_candidates_from_implementation_hits(
  hits : Array[QueryCandidate],
  limit : Int,
) -> Array[OwnerCandidate] {
  let result : Array[OwnerCandidate] = []
  for hit in hits {
    if hit.owner.length() == 0 {
      continue
    }
    match owner_candidate_index(result, hit.owner) {
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
  owner_candidates_prefix(result, limit)
}

///|
fn owner_candidate_index(
  candidates : Array[OwnerCandidate],
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
fn preflight_candidates(
  implementation_hits : Array[QueryCandidate],
  documentation_sources : Array[DocumentationCandidate],
  limit : Int,
) -> Array[QueryCandidate] {
  let result : Array[QueryCandidate] = []
  for candidate in implementation_hits {
    push_unique_query_candidate(result, candidate)
    if result.length() >= limit {
      return result
    }
  }
  for doc in documentation_sources {
    push_unique_query_candidate(result, query_candidate_from_documentation(doc))
    if result.length() >= limit {
      return result
    }
  }
  result
}

///|
fn evidence_candidates(
  implementation_hits : Array[QueryCandidate],
  consumer_candidates : Array[QueryCandidate],
  cli_consumers : Array[QueryCandidate],
  documentation_sources : Array[DocumentationCandidate],
  limit : Int,
) -> Array[EvidenceCandidate] {
  let result : Array[EvidenceCandidate] = []
  for candidate in implementation_hits {
    push_unique_evidence_candidate(
      result,
      evidence_candidate_from_query(candidate),
    )
  }
  for candidate in consumer_candidates {
    push_unique_evidence_candidate(
      result,
      evidence_candidate_from_query(candidate),
    )
  }
  for candidate in cli_consumers {
    push_unique_evidence_candidate(
      result,
      evidence_candidate_from_query(candidate),
    )
  }
  for doc in documentation_sources {
    push_unique_evidence_candidate(
      result,
      evidence_candidate_from_query(query_candidate_from_documentation(doc)),
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
  evidence_candidates_prefix(result, limit)
}

///|
fn query_candidate_from_documentation(
  doc : DocumentationCandidate,
) -> QueryCandidate {
  {
    path: doc.path,
    role: doc.role,
    owner: doc.owner,
    score: doc.score,
    summary_preview: doc.summary_preview,
  }
}

///|
fn evidence_candidate_from_query(
  candidate : QueryCandidate,
) -> EvidenceCandidate {
  {
    path: candidate.path,
    role: candidate.role,
    score: candidate.score,
    summary: evidence_preview_text(candidate.summary_preview),
  }
}

///|
fn push_unique_query_candidate(
  result : Array[QueryCandidate],
  candidate : QueryCandidate,
) -> Unit {
  for existing in result {
    if existing.path == candidate.path {
      return
    }
  }
  result.push(candidate)
}

///|
fn push_unique_evidence_candidate(
  result : Array[EvidenceCandidate],
  candidate : EvidenceCandidate,
) -> Unit {
  for existing in result {
    if existing.path == candidate.path {
      return
    }
  }
  result.push(candidate)
}

///|
fn copy_query_candidates(
  candidates : Array[QueryCandidate],
) -> Array[QueryCandidate] {
  let result : Array[QueryCandidate] = []
  for candidate in candidates {
    result.push(candidate)
  }
  result
}

///|
fn owner_candidates_prefix(
  candidates : Array[OwnerCandidate],
  limit : Int,
) -> Array[OwnerCandidate] {
  let result : Array[OwnerCandidate] = []
  let capped = bounded_count(limit, candidates.length())
  for i in 0..<capped {
    result.push(candidates[i])
  }
  result
}

///|
fn evidence_candidates_prefix(
  candidates : Array[EvidenceCandidate],
  limit : Int,
) -> Array[EvidenceCandidate] {
  let result : Array[EvidenceCandidate] = []
  let capped = bounded_count(limit, candidates.length())
  for i in 0..<capped {
    result.push(candidates[i])
  }
  result
}

///|
fn query_limit_or_default(limit : Int) -> Int {
  if limit <= 0 {
    query_default_limit
  } else {
    limit
  }
}

///|
fn bounded_count(limit : Int, length : Int) -> Int {
  if limit <= 0 || limit > length {
    length
  } else {
    limit
  }
}

///|
fn bounded_text(text : String, max_len : Int) -> String {
  if max_len <= 0 {
    ""
  } else if text.length() <= max_len {
    text
  } else {
    @config_paths.substring(text, 0, max_len)
  }
}

///|
fn evidence_preview_text(text : String) -> String {
  if text.length() <= query_evidence_preview_limit {
    text
  } else {
    @config_paths.substring(text, 0, query_evidence_preview_limit) + "..."
  }
}
