/// # indexion story analyze
///
/// Analyze a story directory and report n:m vocabulary divergence between
/// supply-side documents (plot, references, scene-notes) and the derived
/// prose chapters.

///|
pub struct AnalyzeConfig {
  root : String
  format : String
  output : String
  max_terms : Int
  min_value_length : Int
}

///|
pub fn AnalyzeConfig::from_matches(
  matches : @argparse.Matches,
) -> AnalyzeConfig {
  let get_str = fn(key : String, default_ : String) -> String {
    match matches.values.get(key) {
      Some(arr) => if arr.length() > 0 { arr[0] } else { default_ }
      None => default_
    }
  }
  let get_int = fn(key : String, default_ : Int) -> Int {
    match matches.values.get(key) {
      Some(arr) =>
        if arr.length() > 0 {
          @common.parse_int(arr[0])
        } else {
          default_
        }
      None => default_
    }
  }
  {
    root: get_str("root", ""),
    format: get_str("format", "text"),
    output: get_str("output", ""),
    max_terms: get_int("max-terms", 20),
    min_value_length: get_int("min-value-length", 2),
  }
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command::new(
    "analyze",
    about="Analyze a story directory: report n:m source↔prose divergence",
    options=[
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
    ],
    positionals=[
      @argparse.PositionArg::new(
        "root",
        about="Story root directory containing sources/ and prose/",
        num_args=@argparse.ValueRange::single(),
      ),
    ],
  )
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = AnalyzeConfig::from_matches(matches)
  if config.root.length() == 0 {
    println("Error: story root directory is required.")
    println("")
    println(command().render_help())
    return
  }
  let dataset = match @story.load_story_dataset(config.root) {
    Some(ds) => ds
    None => {
      println(
        "Error: no sources/ or prose/ found under " + config.root + ".",
      )
      println(
        "Expected layout: <root>/sources/{plot,references,scene-notes}/ + <root>/prose/",
      )
      return
    }
  }
  let story_config = @story.StoryConfig::new(
    config.root,
    max_terms=config.max_terms,
    min_value_length=config.min_value_length,
  )
  let report = @story.analyze_story(dataset, story_config)
  let format = @story.StoryFormat::parse(config.format)
  let rendered = @story.render_report(report, format)
  @common.write_output(config.output, rendered, label="Story report")
}
