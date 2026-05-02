/// # indexion story names
///
/// Take names seriously: walk the headings in every `--spec` document
/// and report which ones have drifted from their bodies.
///
/// Each `## heading` in a spec document defines a `NamedEntity`:
/// the heading text is the **name**, the body under the heading is
/// the **content**. The identity package scores how much of the
/// name's vocabulary actually lives in the body, decides an action
/// (Keep / Rename / Split / Hollow), and emits a one-line rationale.
///
/// Folder layout and filename conventions are not used. The user
/// scopes the analysis with globs.

///|
pub struct NamesConfig {
  spec : Array[String]
  format : String
  output : String
}

///|
pub fn NamesConfig::from_matches(matches : @argparse.Matches) -> NamesConfig {
  {
    spec: @common.arg_list(matches, "spec"),
    format: @common.arg_str(matches, "format", "text"),
    output: @common.arg_str(matches, "output", ""),
  }
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command::new(
    "names",
    about="Report name ↔ content drift for every heading in --spec docs",
    options=[
      @argparse.OptionArg(
        "spec",
        action=Append,
        about="Glob pattern for spec-side documents (repeatable)",
      ),
      @argparse.OptionArg::new(
        "format",
        about="Output format: text | json",
        default_values=["text"],
      ),
      @argparse.OptionArg::new(
        "output",
        about="Output file path (- or empty = stdout)",
        default_values=[""],
      ),
    ],
  )
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = NamesConfig::from_matches(matches)
  if config.spec.is_empty() {
    println("Error: at least one --spec pattern is required.")
    println("")
    println(command().render_help())
    return
  }
  let groups = @story.load_groups(config.spec, [])
  if groups.get_spec().is_empty() {
    println("Error: no spec documents matched the given --spec patterns.")
    return
  }
  let registry = resolve_registry()
  let entities = collect_entities(groups, registry)
  let reports : Array[@identity.NameDivergence] = []
  for e in entities {
    reports.push(@identity.score_name_divergence(e, registry))
  }
  let rendered = match config.format {
    "json" => render_json(reports)
    _ => render_text(reports)
  }
  @common.write_output(config.output, rendered, label="Story names report")
}

///|
/// Resolve the same kgfs/story registry the rest of the story commands
/// use. Mirrors the resolution logic in src/story/divergence.mbt
/// (probe `<root>/kgfs/story/` then `<CWD>/kgfs/story/`) so heading
/// extraction sees the same spec.
fn resolve_registry() -> @kgf_registry.KGFRegistry {
  let candidates = ["kgfs/story"]
  for path in candidates {
    if @fs.path_exists(path) {
      return @kgf_registry.KGFRegistry::load_from_dir(path)
    }
  }
  @kgf_registry.KGFRegistry::new()
}

///|
/// Walk every spec document, split it into sections via the project
/// SoT, and turn each (heading, body) into a `NamedEntity`. Heading-
/// less docs are not included — there is no name to disagree with.
fn collect_entities(
  groups : @story.StoryGroups,
  registry : @kgf_registry.KGFRegistry,
) -> Array[@identity.NamedEntity] {
  let result : Array[@identity.NamedEntity] = []
  for s in groups.get_spec() {
    let sections = @doc_structure.load_document_sections(
      s.get_content(),
      s.get_path(),
      Some(registry),
    )
    if sections.length() == 0 {
      // No headings → treat the whole doc as one named entity using
      // the path stem as the name.
      let title = path_stem(s.get_path())
      result.push(
        @identity.NamedEntity::new(
          name=@identity.Name::single(title),
          content=s.get_content(),
          origin=s.get_path(),
        ),
      )
      continue
    }
    for section in sections {
      result.push(
        @identity.NamedEntity::new(
          name=@identity.Name::single(section.title),
          content=section.content,
          origin=s.get_path(),
        ),
      )
    }
  }
  result
}

///|
fn path_stem(path : String) -> String {
  let base = @config_paths.basename(path)
  let ext = @config_paths.extension(base)
  if ext.length() == 0 || ext.length() >= base.length() {
    return base
  }
  let stem_len = base.length() - ext.length()
  @config_paths.substring(base, 0, stem_len)
}

///|
fn render_text(reports : Array[@identity.NameDivergence]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("=== indexion story names ===\n")
  buf.write_string("Entities: " + reports.length().to_string() + "\n")
  buf.write_string("\n")
  let mut keep = 0
  let mut rename = 0
  let mut split = 0
  let mut hollow = 0
  for r in reports {
    match r.get_action() {
      @identity.NameAction::Keep => keep += 1
      @identity.NameAction::Rename => rename += 1
      @identity.NameAction::Split => split += 1
      @identity.NameAction::Hollow => hollow += 1
    }
  }
  buf.write_string(
    "Summary: keep=" +
    keep.to_string() +
    " rename=" +
    rename.to_string() +
    " split=" +
    split.to_string() +
    " hollow=" +
    hollow.to_string() +
    "\n\n",
  )
  buf.write_string("== Candidates ==\n")
  for r in reports {
    let entity = r.get_entity()
    let name = entity.get_name()
    if r.get_action() is @identity.NameAction::Keep {
      continue
    }
    buf.write_string("\n")
    buf.write_string("[" + entity.get_origin() + "] " + name.get_display() + "\n")
    buf.write_string("  action: " + r.get_rationale() + "\n")
    let unused = r.get_prominent_unused()
    if unused.length() > 0 {
      buf.write_string("  prominent body terms: ")
      for i, t in unused {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(t)
      }
      buf.write_string("\n")
    }
  }
  if rename + split + hollow == 0 {
    buf.write_string("\n(All entity names fit their bodies.)\n")
  }
  buf.to_string()
}

///|
fn render_json(reports : Array[@identity.NameDivergence]) -> String {
  let arr : Array[Json] = []
  for r in reports {
    arr.push(r.to_json())
  }
  let json : Json = arr.to_json()
  json.stringify(indent=2) + "\n"
}
