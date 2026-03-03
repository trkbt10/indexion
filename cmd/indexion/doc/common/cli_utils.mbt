// Shared CLI utilities for doc subcommands.

///|
/// Extract value after '=' in argument string, starting at the given position.
pub fn get_arg_value(arg : String, start : Int) -> String {
  let chars = arg.to_array()
  if start >= chars.length() {
    return ""
  }
  let result : Array[Char] = []
  for i = start; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Load all KGF specs from a directory.
pub fn load_specs(specs_dir : String) -> Map[String, @kgf_types.KGFSpec] {
  let specs : Map[String, @kgf_types.KGFSpec] = {}
  try {
    if not(@fs.is_dir(specs_dir)) {
      println("Warning: Specs directory not found: " + specs_dir)
      return specs
    }
    let entries = @fs.read_dir(specs_dir)
    for entry in entries {
      if entry.has_suffix(".kgf") {
        let path = specs_dir + "/" + entry
        let content = @fs.read_file_to_string(path)
        match @parser.parse_kgf(content) {
          Some(spec) => {
            let lang = spec.get_language()
            specs.set(lang, spec)
          }
          None => println("Warning: Failed to parse spec: " + path)
        }
      }
    }
  } catch {
    e => println("Warning: Could not load specs: " + e.to_string())
  }
  specs
}

///|
/// Collect files from a path (file or directory), recursively.
pub fn collect_files(path : String, files : Array[(String, String)]) -> Unit {
  let clean_path = trim_trailing_slash(path)
  try {
    if @fs.is_dir(clean_path) {
      let entries = @fs.read_dir(clean_path)
      for entry in entries {
        let full_path = clean_path + "/" + entry
        collect_files(full_path, files)
      }
    } else if @fs.is_file(clean_path) {
      if is_supported_file(clean_path) {
        let content = @fs.read_file_to_string(clean_path)
        files.push((clean_path, content))
      }
    }
  } catch {
    e =>
      println(
        "Warning: Could not read " + clean_path + ": " + e.to_string(),
      )
  }
}

///|
/// Remove trailing slash from path.
pub fn trim_trailing_slash(path : String) -> String {
  if path.length() > 0 && path.has_suffix("/") {
    let chars = path.to_array()
    let result : Array[Char] = []
    for i = 0; i < chars.length() - 1; i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    path
  }
}

///|
/// Check if file extension is supported for analysis.
pub fn is_supported_file(path : String) -> Bool {
  let extensions = [
    ".ts", ".tsx", ".js", ".jsx", ".mjs", ".mbt", ".py", ".go", ".rs", ".sql",
    ".html", ".css", ".md",
  ]
  for ext in extensions {
    if path.has_suffix(ext) {
      return true
    }
  }
  false
}

///|
/// Write string content to a file.
pub fn write_output(path : String, content : String) -> Bool {
  try {
    @fs.write_string_to_file(path, content)
    true
  } catch {
    e => {
      println("Write error: " + e.to_string())
      false
    }
  }
}

///|
/// Join array of strings with newline separator.
pub fn join_lines(lines : Array[String]) -> String {
  if lines.length() == 0 {
    return ""
  }
  let result : Array[Char] = []
  for i, line in lines {
    if i > 0 {
      result.push('\n')
    }
    for c in line {
      result.push(c)
    }
  }
  String::from_array(result)
}
