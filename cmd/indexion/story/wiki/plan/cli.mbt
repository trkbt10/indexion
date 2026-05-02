/// # indexion story wiki plan
///
/// Print the page proposals for a given spec document group. No writes.

///|
pub struct PlanConfig {
  spec : Array[String]
  format : String
  output : String
}

///|
pub fn PlanConfig::from_matches(matches : @argparse.Matches) -> PlanConfig {
  {
    spec: @common.arg_list(matches, "spec"),
    format: @common.arg_str(matches, "format", "text"),
    output: @common.arg_str(matches, "output", ""),
  }
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command::new(
    "plan",
    about="Propose story wiki pages from --spec documents",
    options=[
      @argparse.OptionArg(
        "spec",
        action=Append,
        about="Glob pattern for spec-side documents (repeatable)",
      ),
      @argparse.OptionArg::new(
        "format",
        about="Output format: text | md | json",
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
  let config = PlanConfig::from_matches(matches)
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
  let plan = @story_wiki.plan_story_wiki(groups)
  let format = @story_wiki.PlanFormat::parse(config.format)
  let rendered = @story_wiki.render_plan(plan, format)
  @common.write_output(config.output, rendered, label="Story wiki plan")
}
