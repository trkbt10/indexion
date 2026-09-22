///|
/// Rank task terms for file and owner matching, suppressing consumer-dominated
/// terms that would point agents at adapters instead of implementation owners.
pub fn filter_task_terms(
  terms : Array[String],
  briefs : Array[LocalFileBrief],
) -> Array[String] {
  if briefs.is_empty() {
    return terms
  }
  let ranked : Array[LocalTermRank] = []
  for term in terms {
    let mut owner_docs = 0
    let mut consumer_docs = 0
    for brief in briefs {
      if brief.summary_terms.contains(term) {
        if brief_is_consumer(brief) {
          consumer_docs += 1
        } else {
          owner_docs += 1
        }
      }
    }
    let docs = owner_docs + consumer_docs
    if docs > 0 && !is_consumer_dominated_term(term, briefs) {
      ranked.push({ term, owner_docs, consumer_docs, all_docs: docs, })
    }
  }
  ranked.sort_by(fn(a, b) {
    let a_owner_missing = if a.owner_docs == 0 { 1 } else { 0 }
    let b_owner_missing = if b.owner_docs == 0 { 1 } else { 0 }
    let c = a_owner_missing.compare(b_owner_missing)
    if c != 0 {
      return c
    }
    let c = a.owner_docs.compare(b.owner_docs)
    if c != 0 {
      return c
    }
    let c = a.consumer_docs.compare(b.consumer_docs)
    if c != 0 {
      return c
    }
    let c = a.all_docs.compare(b.all_docs)
    if c != 0 {
      c
    } else {
      b.term.length().compare(a.term.length())
    }
  })
  let result : Array[String] = []
  for item in ranked {
    result.push(item.term)
  }
  result
}

///|
pub fn filter_owner_task_terms(
  terms : Array[String],
  orient_map : AgentOrientMap,
) -> Array[String] {
  if orient_map.owners.is_empty() {
    return terms
  }
  let ranked : Array[LocalTermRank] = []
  let owner_terms : Array[Array[String]] = []
  for owner in orient_map.owners {
    owner_terms.push(task_tokens(owner.summary))
  }
  for term in terms {
    let mut owner_docs = 0
    for tokens in owner_terms {
      if tokens.contains(term) {
        owner_docs += 1
      }
    }
    if owner_docs > 0 {
      ranked.push({ term, owner_docs, consumer_docs: 0, all_docs: owner_docs, })
    }
  }
  ranked.sort_by(fn(a, b) {
    let c = a.owner_docs.compare(b.owner_docs)
    if c != 0 {
      c
    } else {
      b.term.length().compare(a.term.length())
    }
  })
  let result : Array[String] = []
  for item in ranked {
    result.push(item.term)
  }
  result
}

///|
pub fn owner_task_terms_from_map(
  raw_terms : Array[String],
  orient_map : AgentOrientMap,
) -> Array[String] {
  let focused = filter_owner_task_terms(raw_terms, orient_map)
  if focused.length() > 0 {
    focused
  } else {
    raw_terms
  }
}

///|
pub fn is_consumer_dominated_term(
  term : String,
  briefs : Array[LocalFileBrief],
) -> Bool {
  let mut consumer_docs = 0
  let mut owner_docs = 0
  for brief in briefs {
    if !brief.structural_terms.contains(term) {
      continue
    }
    if brief_is_consumer(brief) {
      consumer_docs += 1
    } else {
      owner_docs += 1
    }
  }
  consumer_docs >= 3 && consumer_docs > owner_docs
}
