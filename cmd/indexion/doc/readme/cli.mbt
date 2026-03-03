///|
/// # indexion doc readme
///
/// Generate README.md files from source code documentation.
///
/// ## Overview
///
/// Extracts `///` documentation comments from MoonBit source files and
/// generates README.md files for each package, plus an aggregated root README.
///
/// ## Usage
///
/// ```bash
/// indexion doc readme [options] [directory]
/// ```
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--config=FILE` | Configuration file | doc.json |
/// | `--root-only` | Generate only root README | false |
/// | `--packages-only` | Generate only package READMEs | false |
///
/// ## Examples
///
/// ```bash
/// # Generate all READMEs from doc.json config
/// indexion doc readme
///
/// # Generate only root README
/// indexion doc readme --root-only
///
/// # Use custom config
/// indexion doc readme --config=custom-doc.json
/// ```

///|
/// Configuration for README generation.
pub struct ReadmeConfig {
  config_file : String
  root_only : Bool
  packages_only : Bool
  target_dir : String
  show_help : Bool
}

///|
pub fn ReadmeConfig::default() -> ReadmeConfig {
  {
    config_file: "doc.json",
    root_only: false,
    packages_only: false,
    target_dir: ".",
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
pub fn parse_args(args : Array[String], start_idx : Int) -> ReadmeConfig {
  let mut config = ReadmeConfig::default()
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg == "--root-only" {
      config = { ..config, root_only: true }
    } else if arg == "--packages-only" {
      config = { ..config, packages_only: true }
    } else if arg.has_prefix("--config=") {
      let value = get_arg_value(arg, 9)
      config = { ..config, config_file: value }
    } else if not(arg.has_prefix("-")) && config.target_dir == "." {
      config = { ..config, target_dir: arg }
    }
  }
  config
}

///|
pub fn show_help() -> Unit {
  println("indexion doc readme - Generate README.md from source documentation")
  println("")
  println("Usage:")
  println("  indexion doc readme [options] [directory]")
  println("")
  println("Options:")
  println("  --config=FILE      Configuration file (default: doc.json)")
  println("  --root-only        Generate only root README")
  println("  --packages-only    Generate only package READMEs")
  println("  --help             Show this help message")
  println("")
  println("Examples:")
  println("  indexion doc readme")
  println("  indexion doc readme --root-only")
  println("  indexion doc readme --config=custom.json")
}

///|
/// Extract documentation from a MoonBit file.
/// Returns the first `///` block that starts with `# `.
fn extract_doc_from_file(path : String) -> String? {
  try {
    let content = @fs.read_file_to_string(path)
    extract_doc_block(content)
  } catch {
    _ => None
  }
}

///|
/// Extract the main documentation block from content.
fn extract_doc_block(content : String) -> String? {
  let lines = split_lines(content)
  let doc_lines : Array[String] = []
  let mut in_doc = false
  let mut found_header = false
  for line in lines {
    if line.has_prefix("///") {
      let doc_content = if line.length() > 3 {
        let chars = line.to_array()
        let result : Array[Char] = []
        // Skip "/// " or "///"
        let start = if chars.length() > 4 && chars[3] == ' ' { 4 } else { 3 }
        for i = start; i < chars.length(); i = i + 1 {
          result.push(chars[i])
        }
        String::from_array(result)
      } else {
        ""
      }
      // Check if this is a header line (starts with #)
      if doc_content.has_prefix("# ") && not(found_header) {
        found_header = true
        in_doc = true
      }
      if in_doc {
        doc_lines.push(doc_content)
      }
    } else if in_doc && found_header {
      // End of doc block
      break
    }
  }
  if doc_lines.length() > 0 {
    Some(join_lines(doc_lines))
  } else {
    None
  }
}

///|
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let chars = s.to_array()
  let current : Array[Char] = []
  for c in chars {
    if c == '\n' {
      lines.push(String::from_array(current.copy()))
      current.clear()
    } else if c != '\r' {
      current.push(c)
    }
  }
  if current.length() > 0 {
    lines.push(String::from_array(current))
  }
  lines
}

///|
fn join_lines(lines : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i, line in lines {
    if i > 0 {
      buf.write_char('\n')
    }
    buf.write_string(line)
  }
  buf.to_string()
}

///|
/// Find main source file in a package directory.
fn find_main_source(dir : String) -> String? {
  try {
    // Priority: cli.mbt, main.mbt, then any .mbt file
    let candidates = ["cli.mbt", "main.mbt"]
    for candidate in candidates {
      let path = dir + "/" + candidate
      if @fs.is_file(path) {
        return Some(path)
      }
    }
    // Fallback to first .mbt file
    let entries = @fs.read_dir(dir)
    for entry in entries {
      if entry.has_suffix(".mbt") && not(entry.has_suffix("_wbtest.mbt")) {
        return Some(dir + "/" + entry)
      }
    }
    None
  } catch {
    _ => None
  }
}

///|
/// Generate README for a single package.
fn generate_package_readme(pkg_path : String) -> Bool {
  match find_main_source(pkg_path) {
    Some(src_path) => {
      match extract_doc_from_file(src_path) {
        Some(doc) => {
          let readme_path = pkg_path + "/README.md"
          try {
            @fs.write_string_to_file(readme_path, doc + "\n")
            println("  Generated: " + readme_path)
            true
          } catch {
            e => {
              println("  Error writing " + readme_path + ": " + e.to_string())
              false
            }
          }
        }
        None => {
          println("  Skipped: " + pkg_path + " (no documentation found)")
          false
        }
      }
    }
    None => {
      println("  Skipped: " + pkg_path + " (no source file found)")
      false
    }
  }
}

///|
/// Read static file content.
fn read_static_file(path : String) -> String {
  try {
    @fs.read_file_to_string(path)
  } catch {
    _ => ""
  }
}

///|
/// Generate root README by combining static content and package docs.
fn generate_root_readme(base_dir : String) -> Bool {
  let buf = StringBuilder::new()
  // Read intro
  let intro = read_static_file(base_dir + "/docs/intro.md")
  if intro.length() > 0 {
    buf.write_string(intro)
    buf.write_string("\n\n")
  }
  // Commands section
  buf.write_string("## Commands\n\n")
  let cmd_packages = [
    ("explore", "cmd/indexion/explore"),
    ("plan refactor", "cmd/indexion/plan/refactor"),
    ("doc gen", "cmd/indexion/doc/gen"),
    ("doc readme", "cmd/indexion/doc/readme"),
    ("sim", "cmd/indexion/similarity"),
  ]
  for item in cmd_packages {
    let (name, path) = item
    let readme_path = base_dir + "/" + path + "/README.md"
    let file_exists = try {
      @fs.is_file(readme_path)
    } catch {
      _ => false
    }
    if file_exists {
      buf.write_string("### `indexion " + name + "`\n\n")
      let content = read_static_file(readme_path)
      // Extract just the overview and usage sections
      let summary = extract_summary(content)
      buf.write_string(summary)
      buf.write_string("\n\n")
      buf.write_string("[Full documentation](" + path + "/README.md)\n\n")
    }
  }
  // Installation
  let installation = read_static_file(base_dir + "/docs/installation.md")
  if installation.length() > 0 {
    buf.write_string(installation)
    buf.write_string("\n")
  }
  // License
  buf.write_string("## License\n\nApache License 2.0\n")
  let readme_path = base_dir + "/README.md"
  try {
    @fs.write_string_to_file(readme_path, buf.to_string())
    println("Generated: " + readme_path)
    true
  } catch {
    e => {
      println("Error writing " + readme_path + ": " + e.to_string())
      false
    }
  }
}

///|
/// Extract summary (Overview section) from README content.
fn extract_summary(content : String) -> String {
  let lines = split_lines(content)
  let result : Array[String] = []
  let mut in_overview = false
  let mut section_count = 0
  for line in lines {
    if line.has_prefix("## Overview") {
      in_overview = true
      continue
    }
    if in_overview {
      if line.has_prefix("## ") {
        section_count = section_count + 1
        if section_count > 1 {
          break
        }
        // Include Usage section too
        if line.has_prefix("## Usage") {
          result.push(line)
        } else {
          break
        }
      } else {
        result.push(line)
      }
    }
  }
  join_lines(result)
}

///|
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  let base_dir = config.target_dir
  println("=== indexion doc readme ===")
  println("Base directory: " + base_dir)
  println("")
  // Generate package READMEs
  if not(config.root_only) {
    println("Generating package READMEs...")
    let packages = [
      "cmd/indexion",
      "cmd/indexion/explore",
      "cmd/indexion/plan",
      "cmd/indexion/plan/refactor",
      "cmd/indexion/doc",
      "cmd/indexion/doc/gen",
      "cmd/indexion/doc/readme",
      "cmd/indexion/similarity",
    ]
    for pkg in packages {
      let pkg_path = if base_dir == "." { pkg } else { base_dir + "/" + pkg }
      let _ = generate_package_readme(pkg_path)

    }
    println("")
  }
  // Generate root README
  if not(config.packages_only) {
    println("Generating root README...")
    let _ = generate_root_readme(base_dir)

  }
  println("")
  println("Done!")
}
