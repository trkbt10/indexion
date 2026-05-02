/// Materialise a `StoryWikiPlan` on disk by calling the existing wiki
/// manifest SoT (`@wiki_manifest::write_page`) plus the wiki log.
///
/// The wiki directory is supplied by the caller — there is no default
/// convention. The CLI surfaces `--wiki-dir` as a required flag so the
/// user makes the choice explicitly. The manifest is auto-initialised
/// by `load_manifest` when the directory does not yet contain one.
///
/// The builder is idempotent on page ids: when a manifest already lists
/// a proposed id, that proposal is skipped (reported in
/// `BuildResult.skipped`) rather than overwriting handcrafted prose.
/// Re-running after editing the spec docs is safe — only new pages
/// appear.

///|
/// Apply a plan to disk. Returns the build summary or None on a wiki I/O
/// failure (manifest could not be loaded).
pub fn build_story_wiki(
  plan : StoryWikiPlan,
  wiki_dir : String,
  actor : String,
) -> BuildResult? {
  let manifest = match @wiki_manifest.load_manifest(wiki_dir) {
    Some(m) => m
    None => return None
  }
  let written : Array[String] = []
  let skipped : Array[String] = []
  let mut current_manifest = manifest
  for proposal in plan.get_proposals() {
    if manifest_contains(current_manifest, proposal.id) {
      skipped.push(proposal.id)
      continue
    }
    let new_page = @wiki_types.ManifestPage::new(
      id=proposal.id,
      title=proposal.title,
      file=proposal.id + ".md",
      sources=proposal.sources,
      provenance=Some("synthesized"),
      last_actor=Some(actor),
    )
    let next_pages : Array[@wiki_types.ManifestPage] = []
    for mp in current_manifest.pages {
      next_pages.push(mp)
    }
    next_pages.push(new_page)
    let next_manifest = @wiki_types.WikiManifest::new(
      title=current_manifest.title,
      pages=next_pages,
    )
    if !@wiki_manifest.write_page(
      wiki_dir, next_manifest, proposal.id, proposal.content,
    ) {
      // write_page already printed the error; abort the rest of the build
      // so the manifest does not get further out of sync with the disk.
      return Some({ written, skipped })
    }
    current_manifest = next_manifest
    written.push(proposal.id)
  }
  if written.length() > 0 {
    let log = @wiki_log.WikiLog::load(wiki_dir)
    log.append(
      @wiki_log.WikiLogEntry::new(
        timestamp=@env.now(),
        operation="story wiki build",
        actor~,
        summary="Built " +
        written.length().to_string() +
        " story wiki page(s)",
        affected_pages=written,
      ),
    )
    log.save(wiki_dir)
  }
  Some({ written, skipped })
}

///|
fn manifest_contains(
  manifest : @wiki_types.WikiManifest,
  id : String,
) -> Bool {
  for mp in manifest.pages {
    if mp.id == id {
      return true
    }
  }
  false
}
