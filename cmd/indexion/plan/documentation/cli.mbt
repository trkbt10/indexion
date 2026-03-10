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

///|
pub struct DocPlanConfig {
  target_dir : String
  output : String
  style : String // "coverage", "full"
  format : String // "md", "json", "github-issue"
  template : String // path to GitHub Issue Form template
  project_name : String
  show_help : Bool
}

///|
pub fn DocPlanConfig::default() -> DocPlanConfig {
  {
    target_dir: "",
    output: "",
    style: "full",
    format: "md",
    template: "",
    project_name: "",
    show_help: false,
  }
}

///|
fn get_arg_value(arg : String, prefix_len : Int) -> String {
  let chars = arg.to_array()
  if prefix_len >= chars.length() {
    return ""
  }
  let result : Array[Char] = []
  for i = prefix_len; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
pub fn parse_args(args : Array[String], start_idx : Int) -> DocPlanConfig {
  let mut config = DocPlanConfig::default()
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg.has_prefix("--output=") || arg.has_prefix("-o=") {
      let prefix_len = if arg.has_prefix("--output=") { 9 } else { 3 }
      let value = get_arg_value(arg, prefix_len)
      config = { ..config, output: value }
    } else if arg.has_prefix("--style=") {
      let value = get_arg_value(arg, 8)
      config = { ..config, style: value }
    } else if arg.has_prefix("--format=") {
      let value = get_arg_value(arg, 9)
      config = { ..config, format: value }
    } else if arg.has_prefix("--template=") {
      let value = get_arg_value(arg, 11)
      config = { ..config, template: value }
    } else if arg.has_prefix("--name=") {
      let value = get_arg_value(arg, 7)
      config = { ..config, project_name: value }
    } else if not(arg.has_prefix("-")) && config.target_dir.length() == 0 {
      config = { ..config, target_dir: arg }
    }
  }
  config
}

///|
pub fn show_help() -> Unit {
  println(
    "indexion plan documentation - Generate documentation coverage analysis",
  )
  println("")
  println("Usage:")
  println("  indexion plan documentation [options] <directory>")
  println("")
  println("Options:")
  println("  --output=FILE, -o=   Output file path (default: stdout)")
  println("  --style=STYLE        Output style: coverage, full (default: full)")
  println(
    "  --format=FORMAT      Output format: md, json, github-issue (default: md)",
  )
  println("  --template=FILE      GitHub Issue Form template (.yml)")
  println(
    "  --name=NAME          Project name (auto-detect from moon.mod.json)",
  )
  println("  --help               Show this help message")
  println("")
  println("Styles:")
  println("  coverage   Documentation coverage analysis only")
  println("  full       Complete documentation plan with action items")
  println("")
  println("Formats:")
  println("  md           Standard Markdown output")
  println("  json         JSON intermediate representation")
  println("  github-issue GitHub Issue format with title and body")
  println("")
  println("Examples:")
  println("  indexion plan documentation src/")
  println("  indexion plan documentation --format=github-issue src/")
  println(
    "  indexion plan documentation --template=.github/ISSUE_TEMPLATE/doc.yml src/",
  )
}

///|
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  if config.target_dir.length() == 0 {
    println("Error: Directory path required.")
    println("")
    show_help()
    return
  }
  // Load project info from moon.mod.json if available
  let project_info = load_project_info(config.target_dir)
  let project_name = if config.project_name.length() > 0 {
    config.project_name
  } else {
    project_info.name
  }
  // Analyze documentation coverage
  let analysis = analyze_documentation(config.target_dir)
  // Generate output based on format
  let output_content = render_output(
    config, analysis, project_info, project_name,
  )
  // Output
  if config.output.length() > 0 {
    try {
      @fs.write_string_to_file(config.output, output_content)
      println("Documentation plan written to: " + config.output)
    } catch {
      e => println("Error writing file: " + e.to_string())
    }
  } else {
    println(output_content)
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
            format_github_issue(issue)
          }
        }
      } else {
        let issue = @plan_render.render_github_issue(doc)
        format_github_issue(issue)
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

///|
fn format_github_issue(issue : @plan_render.GitHubIssue) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# ")
  buf.write_string(issue.title)
  buf.write_string("\n\n")
  if issue.labels.length() > 0 {
    buf.write_string("**Labels:** ")
    for i, label in issue.labels {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string("`")
      buf.write_string(label)
      buf.write_string("`")
    }
    buf.write_string("\n\n")
  }
  buf.write_string("---\n\n")
  buf.write_string(issue.body)
  buf.to_string()
}
