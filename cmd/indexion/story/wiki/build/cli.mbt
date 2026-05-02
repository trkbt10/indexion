/// # indexion story wiki build
///
/// Materialise the story wiki plan to disk. The wiki dir is mandatory
/// (`--wiki-dir`) so the user explicitly chooses where the wiki lives.
/// Existing pages with the same id are skipped (idempotent re-runs are
/// safe — only new pages appear).

///|
pub struct BuildConfig {
  spec : Array[String]
  wiki_dir : String
  actor : String
}

///|
pub fn BuildConfig::from_matches(matches : @argparse.Matches) -> BuildConfig {
  let get_str = fn(key : String, default_ : String) -> String {
    match matches.values.get(key) {
      Some(arr) => if arr.length() > 0 { arr[0] } else { default_ }
      None => default_
    }
  }
  let get_list = fn(key : String) -> Array[String] {
    match matches.values.get(key) {
      Some(arr) => arr
      None => []
    }
  }
  {
    spec: get_list("spec"),
    wiki_dir: get_str("wiki-dir", ""),
    actor: get_str("actor", "indexion"),
  }
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command::new(
    "build",
    about="Build story wiki pages from --spec docs into --wiki-dir",
    options=[
      @argparse.OptionArg(
        "spec",
        action=Append,
        about="Glob pattern for spec-side documents (repeatable)",
      ),
      @argparse.OptionArg::new(
        "wiki-dir",
        about="Wiki directory (e.g. .indexion/story-wiki)",
        default_values=[""],
      ),
      @argparse.OptionArg::new(
        "actor",
        about="Who is building: indexion, agent:<name>, user",
        default_values=["indexion"],
      ),
    ],
  )
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = BuildConfig::from_matches(matches)
  if config.spec.is_empty() {
    println("Error: at least one --spec pattern is required.")
    println("")
    println(command().render_help())
    return
  }
  if config.wiki_dir.length() == 0 {
    println("Error: --wiki-dir is required.")
    println("")
    println(command().render_help())
    return
  }
  let groups = @story.load_groups(config.spec, [])
  if groups.get_spec().is_empty() {
    println("Error: no spec documents matched the given --spec patterns.")
    return
  }
  let plan = @story_wiki.plan_story_wiki(groups)
  match @story_wiki.build_story_wiki(plan, config.wiki_dir, config.actor) {
    None => println("Error: failed to build story wiki at " + config.wiki_dir)
    Some(result) => {
      println("Wrote " + result.written.length().to_string() + " page(s):")
      for id in result.written {
        println("  + " + id)
      }
      if result.skipped.length() > 0 {
        println(
          "Skipped " +
          result.skipped.length().to_string() +
          " existing page(s):",
        )
        for id in result.skipped {
          println("  = " + id)
        }
      }
      println("")
      println("Wiki directory: " + config.wiki_dir)
    }
  }
}
