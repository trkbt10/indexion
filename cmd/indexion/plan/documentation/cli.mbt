///|
/// # indexion plan documentation
///
/// Generate documentation coverage analysis and README templates.
///
/// ## Usage
///
/// ```bash
/// indexion plan documentation [options] <directory>
/// ```
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--output=FILE`, `-o=` | Output file path | stdout |
/// | `--style=STYLE` | Output style: coverage, full | full |
/// | `--format=FORMAT` | Output format: md, json, github-issue | md |
/// | `--template=FILE` | GitHub Issue Form template (.yml) | - |
/// | `--name=NAME` | Project name (auto-detect from moon.mod.json) | - |
/// | `--specs-dir=DIR` | KGF specs directory | kgfs |

///|
/// CLI configuration for the documentation plan subcommand.
pub(all) struct DocPlanConfig {
  target_dir : String
  output : String
  style : String // "coverage", "full"
  format : String // "md", "json", "github-issue"
  template : String // path to GitHub Issue Form template
  project_name : String
  specs_dir : String // KGF specs directory
}

///|
/// Create default configuration for the documentation plan subcommand.
pub fn DocPlanConfig::default() -> DocPlanConfig {
  {
    target_dir: "",
    output: "",
    style: "full",
    format: "md",
    template: "",
    project_name: "",
    specs_dir: "kgfs",
  }
}

///|
/// Create DocPlanConfig from argparse matches.
pub fn DocPlanConfig::from_matches(
  matches : @argparse.Matches,
) -> DocPlanConfig {
  let output = match matches.values.get("output") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let style = match matches.values.get("style") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "full" }
    _ => "full"
  }
  let format = match matches.values.get("format") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "md" }
    _ => "md"
  }
  let template = match matches.values.get("template") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let project_name = match matches.values.get("name") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let specs_dir = match matches.values.get("specs-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "kgfs" }
    _ => "kgfs"
  }
  let target_dir = match matches.values.get("directory") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  { target_dir, output, style, format, template, project_name, specs_dir }
}

///|
/// Define the documentation command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "documentation",
    about="Generate documentation coverage analysis",
    options=[
      @argparse.OptionArg("output", short='o', about=@help.output),
      @argparse.OptionArg("style", about="Output style: coverage, full", default_values=[
        "full",
      ]),
      @argparse.OptionArg(
        "format",
        about="Output format: md, json, github-issue",
        default_values=["md"],
      ),
      @argparse.OptionArg("template", about="GitHub Issue Form template (.yml)"),
      @argparse.OptionArg(
        "name",
        about="Project name (auto-detect from moon.mod.json)",
      ),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
    ],
    positionals=[
      @argparse.PositionArg("directory", about="Target directory to analyze"),
    ],
  )
}

///|
/// Core documentation analysis. Returns rendered output or None.
pub fn run_to_string(config : DocPlanConfig) -> String? {
  if config.target_dir.length() == 0 {
    return None
  }
  let project_info = load_project_info(config.target_dir)
  let project_name = if config.project_name.length() > 0 {
    config.project_name
  } else {
    project_info.name
  }
  let analysis = analyze_documentation(
    config.target_dir,
    specs_dir=config.specs_dir,
  )
  Some(render_output(config, analysis, project_info, project_name))
}

///|
/// Run the documentation plan command from argparse matches.
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = DocPlanConfig::from_matches(matches)
  match run_to_string(config) {
    Some(output) =>
      @common.write_output(config.output, output, label="Documentation plan")
    None => println(@help.dir_required)
  }
}

///|
fn render_output(
  config : DocPlanConfig,
  analysis : DocAnalysis,
  project_info : ProjectInfo,
  project_name : String,
) -> String {
  match config.format {
    "json" => {
      // Convert to IR and output as JSON
      let doc = to_plan_document(analysis, project_info, project_name)
      doc.to_json().stringify(indent=2)
    }
    "github-issue" => {
      // Convert to IR and render as GitHub Issue
      let doc = to_plan_document(analysis, project_info, project_name)
      if config.template.length() > 0 {
        // Fill template
        match @plan_template.load_issue_form(config.template) {
          Some(template) => {
            let filled = @plan_template.fill_and_render(template, doc)
            let buf = StringBuilder::new()
            buf.write_string("# ")
            buf.write_string(filled.title)
            buf.write_string("\n\n")
            if filled.labels.length() > 0 {
              buf.write_string("**Labels:** ")
              for i, label in filled.labels {
                if i > 0 {
                  buf.write_string(", ")
                }
                buf.write_string("`")
                buf.write_string(label)
                buf.write_string("`")
              }
              buf.write_string("\n\n")
            }
            buf.write_string(filled.body)
            buf.to_string()
          }
          None => {
            println("Warning: Could not load template, using default format")
            let issue = @plan_render.render_github_issue(doc)
            issue.format()
          }
        }
      } else {
        let issue = @plan_render.render_github_issue(doc)
        issue.format()
      }
    }
    _ =>
      // Default: Markdown using legacy renderer for now
      match config.style {
        "coverage" => render_coverage(analysis, project_name)
        _ => {
          // Use new IR-based renderer
          let doc = to_plan_document(analysis, project_info, project_name)
          @plan_render.render_markdown(doc)
        }
      }
  }
}

// format_github_issue: use @plan_render.GitHubIssue::format (SoT)
