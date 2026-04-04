///|
/// # Output Formatting
///
/// Unified output for search results across all content types.

///|
/// Format search results as human-readable text.
fn format_text(
  hits : Array[@search_engine.SearchHit],
  files_only : Bool,
) -> Unit {
  if hits.is_empty() {
    println("No results found.")
    return
  }
  let seen_files : Map[String, Bool] = {}
  for hit in hits {
    let doc = hit.document
    if files_only {
      if !seen_files.contains(doc.source) {
        println(doc.source)
        seen_files[doc.source] = true
      }
    } else {
      let score_str = @common.format_percent(hit.score)
      let location = if doc.line > 0 {
        doc.source + ":" + doc.line.to_string()
      } else {
        doc.source
      }
      let kind_prefix = if doc.kind.length() > 0 { doc.kind + " " } else { "" }
      let lang_suffix = match doc.attrs.get("language") {
        Some(lang) => "  [" + lang + "]"
        None => ""
      }
      println(
        location +
        ": " +
        kind_prefix +
        doc.title +
        "  (" +
        score_str +
        " similar)" +
        lang_suffix,
      )
    }
  }
  println("")
  println(hits.length().to_string() + " results")
}

///|
/// Format search results as JSON.
fn format_json(hits : Array[@search_engine.SearchHit]) -> Unit {
  let arr : Array[Json] = []
  for hit in hits {
    let doc = hit.document
    let m : Map[String, Json] = {}
    m["id"] = doc.id.to_json()
    m["title"] = doc.title.to_json()
    m["source"] = doc.source.to_json()
    m["line"] = doc.line.to_json()
    m["kind"] = doc.kind.to_json()
    m["score"] = hit.score.to_json()
    if !doc.attrs.is_empty() {
      let attrs_json : Map[String, Json] = {}
      for entry in doc.attrs {
        attrs_json[entry.0] = entry.1.to_json()
      }
      m["attrs"] = Json::object(attrs_json)
    }
    arr.push(Json::object(m))
  }
  println(Json::array(arr).stringify(indent=2))
}
