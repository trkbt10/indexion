/// # indexion story analyze
///
/// Measure n:m vocabulary divergence between a `--spec` document group
/// and an `--impl` document group. Both sides accept any number of glob
/// patterns; resolution flows through `@pipeline.discover_files` (SoT).
///
/// Folders and filenames carry no semantic weight. The user picks which
/// files belong to which group; indexion does not classify by name.

///|
pub struct AnalyzeConfig {
  spec : Array[String]
  impl_ : Array[String]
  format : String
  output : String
  max_terms : Int
  min_value_length : Int
  registry_root : String
}

///|
pub fn AnalyzeConfig::from_matches(
  matches : @argparse.Matches,
) -> AnalyzeConfig {
  {
    spec: @common.arg_list(matches, "spec"),
    impl_: @common.arg_list(matches, "impl"),
    format: @common.arg_str(matches, "format", "text"),
    output: @common.arg_str(matches, "output", ""),
    max_terms: @common.arg_int(matches, "max-terms", 20),
    min_value_length: @common.arg_int(matches, "min-value-length", 2),
    registry_root: @common.arg_str(matches, "registry-root", ""),
  }
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command::new(
    "analyze",
    about="Report n:m vocabulary divergence between a --spec group and an --impl group",
    options=[
      @argparse.OptionArg(
        "spec",
        action=Append,
        about="Glob pattern for spec-side documents (repeatable)",
      ),
      @argparse.OptionArg(
        "impl",
        action=Append,
        about="Glob pattern for impl-side documents (repeatable)",
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
      @argparse.OptionArg::new(
        "max-terms",
        about="Maximum divergence terms per side",
        default_values=["20"],
      ),
      @argparse.OptionArg::new(
        "min-value-length",
        about="Minimum length for divergence term values",
        default_values=["2"],
      ),
      @argparse.OptionArg::new(
        "registry-root",
        about="Root for kgfs/story spec discovery (default: CWD)",
        default_values=[""],
      ),
    ],
  )
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = AnalyzeConfig::from_matches(matches)
  if config.spec.is_empty() || config.impl_.is_empty() {
    println(
      "Error: at least one --spec and one --impl pattern is required.",
    )
    println("")
    println(command().render_help())
    return
  }
  let groups = @story.load_groups(config.spec, config.impl_)
  if groups.get_spec().is_empty() {
    println("Error: no spec documents matched the given --spec patterns.")
    return
  }
  if groups.get_impl().is_empty() {
    println("Error: no impl documents matched the given --impl patterns.")
    return
  }
  let story_config = @story.StoryConfig::new(
    max_terms=config.max_terms,
    min_value_length=config.min_value_length,
    registry_root=config.registry_root,
  )
  let report = @story.analyze_story(groups, story_config)
  let format = @story.StoryFormat::parse(config.format)
  let rendered = @story.render_report(report, format)
  @common.write_output(config.output, rendered, label="Story report")
}
