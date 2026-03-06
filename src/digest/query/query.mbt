// Query API for purpose-based function lookup.
// Provides high-level query functions wrapping DigestIndex.

///|
/// Query by purpose and return hits with detailed info.
pub fn query_by_purpose(
  index : @index.DigestIndex,
  purpose : String,
  options : @types.QueryOptions,
) -> Array[@types.QueryHit] {
  let hits = index.query(purpose, options.top_k)
  // Filter by min_score
  let filtered : Array[@types.QueryHit] = []
  for hit in hits {
    if hit.score >= options.min_score {
      // Apply module filter if specified
      let module_ok = match options.filter_module {
        Some(pattern) => hit.function.module_id.contains(pattern)
        None => true
      }
      // Apply kind filter if specified
      let kind_ok = match options.filter_kind {
        Some(kind) => hit.function.symbol.kind == kind
        None => true
      }
      if module_ok && kind_ok {
        filtered.push(hit)
      }
    }
  }
  filtered
}

///|
/// Query by keywords directly (space-separated).
pub fn query_by_keywords(
  index : @index.DigestIndex,
  keywords : String,
  options : @types.QueryOptions,
) -> Array[@types.QueryHit] {
  // Keywords are treated as purpose text
  query_by_purpose(index, keywords, options)
}

///|
/// Format query results as a readable string.
pub fn format_results(hits : Array[@types.QueryHit]) -> String {
  if hits.length() == 0 {
    return "No matching functions found."
  }
  let lines : Array[String] = []
  lines.push("Found " + hits.length().to_string() + " matching symbols:\n")
  for i, hit in hits {
    lines.push(
      (i + 1).to_string() +
      ". " +
      hit.function.name() +
      " (" +
      hit.function.symbol.kind +
      ", " +
      format_score(hit.score) +
      ")",
    )
    // Show doc first if available
    match hit.function.symbol.doc {
      Some(doc) => {
        let short_doc = if doc.length() > 60 {
          (doc[0:60].to_string() catch { _ => "" }) + "..."
        } else {
          doc
        }
        lines.push("   " + short_doc)
      }
      None => ()
    }
    lines.push("   Module: " + hit.function.module_id)
    if hit.function.callers.length() > 0 {
      lines.push("   Callers: " + hit.function.callers.length().to_string())
    }
    if hit.function.callees.length() > 0 {
      lines.push("   Callees: " + hit.function.callees.length().to_string())
    }
    lines.push("")
  }
  lines.join("\n")
}

///|
/// Format score as percentage-like string.
fn format_score(score : Double) -> String {
  let pct = (score * 100.0).to_int()
  pct.to_string() + "%"
}
