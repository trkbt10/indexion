/// Extract `PlotAct` records from spec-side documents.
///
/// Section detection delegates to the project SoT
/// `@doc_structure.load_document_sections`. That function reads the
/// `section_token` and `heading_text_tokens` features from the KGF
/// spec and walks the tokenised content — so the rules for "what
/// counts as a heading and where its body ends" live in
/// `kgfs/story/multilang-prose.kgf`, not in this code.
///
/// The story-prose spec declares `section_token: MdHeading`, so the
/// extractor finds ATX-style markdown headings (`#`, `##`, …). When a
/// document has no headings the SoT returns an empty list; we fall
/// back to "the whole document is a single act" so heading-less spec
/// docs still contribute to reconcile.

///|
/// Extract acts from a single document. `path` is used as the
/// `source_path` of every emitted act so the user can trace a candidate
/// back to its origin.
pub fn extract_acts_from_doc(
  doc : @story.StoryDocument,
  registry : @kgf_registry.KGFRegistry,
) -> Array[PlotAct] {
  let path = doc.get_path()
  let sections = @doc_structure.load_document_sections(
    doc.get_content(),
    path,
    Some(registry),
  )
  if sections.length() == 0 {
    return [whole_doc_as_act(doc)]
  }
  let result : Array[PlotAct] = []
  for i, section in sections {
    let level = section.level.unwrap_or(1)
    result.push({
      source_path: path,
      level,
      index: i + 1,
      title: section.title,
      body: section.content,
    })
  }
  result
}

///|
/// Fallback when a document has no detectable section markers. Title
/// is the path basename via `@config_paths.basename` (SoT).
fn whole_doc_as_act(doc : @story.StoryDocument) -> PlotAct {
  let title = @config_paths.basename(doc.get_path())
  {
    source_path: doc.get_path(),
    level: 1,
    index: 1,
    title,
    body: doc.get_content(),
  }
}

///|
/// Extract all acts from every spec document in a `StoryGroups`, in
/// document order. Multiple spec documents (e.g. v1 and v2 plots) are
/// concatenated; downstream ranking distinguishes them via
/// `source_path`.
pub fn extract_acts(
  groups : @story.StoryGroups,
  registry : @kgf_registry.KGFRegistry,
) -> Array[PlotAct] {
  let result : Array[PlotAct] = []
  for s in groups.get_spec() {
    let acts = extract_acts_from_doc(s, registry)
    for a in acts {
      result.push(a)
    }
  }
  result
}
