///|
/// Assemble root README from package documentation.
pub fn assemble_root_readme(
  packages : Array[(PackageInfo, ExtractedDoc)],
  base_dir : String,
) -> String {
  let buf = StringBuilder::new()
  // Read intro
  let intro = read_static_file(base_dir + "/docs/intro.md")
  if intro.length() > 0 {
    buf.write_string(intro)
    buf.write_string("\n\n")
  }
  // Commands section (dynamically generated from packages)
  let cmd_packages = filter_command_packages(packages)
  if cmd_packages.length() > 0 {
    buf.write_string("## Commands\n\n")
    for item in cmd_packages {
      let (pkg, doc) = item
      let cmd_name = extract_command_name(pkg.path)
      buf.write_string("### `indexion " + cmd_name + "`\n\n")
      let summary = extract_summary(doc.content)
      buf.write_string(summary)
      buf.write_string("\n\n")
      buf.write_string("[Full documentation](" + pkg.path + "/README.md)\n\n")
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
  buf.to_string()
}

///|
/// Read static file content.
fn read_static_file(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ => ""
  }
}

///|
/// Filter packages that are commands (under cmd/).
fn filter_command_packages(
  packages : Array[(PackageInfo, ExtractedDoc)],
) -> Array[(PackageInfo, ExtractedDoc)] {
  let result : Array[(PackageInfo, ExtractedDoc)] = []
  for item in packages {
    let (pkg, doc) = item
    // Handle both "cmd/" and "./cmd/" prefixes
    if pkg.path.has_prefix("cmd/") || pkg.path.has_prefix("./cmd/") {
      result.push((pkg, doc))
    }
  }
  result
}

///|
/// Extract command name from package path.
/// e.g., "cmd/indexion/explore" -> "explore"
/// e.g., "cmd/indexion/doc/readme" -> "doc readme"
fn extract_command_name(path : String) -> String {
  // Handle both "cmd/indexion/" and "./cmd/indexion/" prefixes
  let prefixes = ["./cmd/indexion/", "cmd/indexion/"]
  for prefix in prefixes {
    if path.has_prefix(prefix) {
      let chars = path.to_array()
      let result : Array[Char] = []
      for i = prefix.length(); i < chars.length(); i = i + 1 {
        if chars[i] == '/' {
          result.push(' ')
        } else {
          result.push(chars[i])
        }
      }
      return String::from_array(result)
    }
  }
  path
}

///|
/// Generate root README and write to file.
pub fn generate_root_readme(
  packages : Array[(PackageInfo, ExtractedDoc)],
  base_dir : String,
) -> Bool {
  let content = assemble_root_readme(packages, base_dir)
  let readme_path = base_dir + "/README.md"
  try {
    @fs.write_string_to_file(readme_path, content)
    println("Generated: " + readme_path)
    true
  } catch {
    e => {
      println("Error writing " + readme_path + ": " + e.to_string())
      false
    }
  }
}
