///|
/// Common CLI argument parsing utilities.
/// SoT for argument parsing functions used across CLI commands.

///|
/// Parse a double from string.
/// Handles negative numbers and decimal points.
pub fn parse_double(s : String) -> Double {
  let chars = s.to_array()
  if chars.length() == 0 {
    return 0.0
  }
  let mut result = 0.0
  let mut decimal_place = 0
  let mut is_negative = false
  let mut i = 0
  if chars[0] == '-' {
    is_negative = true
    i = 1
  }
  while i < chars.length() {
    let c = chars[i]
    if c == '.' {
      decimal_place = 1
    } else if c >= '0' && c <= '9' {
      let digit = (c.to_int() - '0'.to_int()).to_double()
      if decimal_place > 0 {
        let mut divisor = 1.0
        for j = 0; j < decimal_place; j = j + 1 {
          divisor = divisor * 10.0
        }
        result = result + digit / divisor
        decimal_place = decimal_place + 1
      } else {
        result = result * 10.0 + digit
      }
    }
    i = i + 1
  }
  if is_negative {
    -result
  } else {
    result
  }
}

///|
/// Parse an integer from string.
pub fn parse_int(s : String) -> Int {
  let chars = s.to_array()
  if chars.length() == 0 {
    return 0
  }
  let mut result = 0
  let mut is_negative = false
  let mut i = 0
  if chars[0] == '-' {
    is_negative = true
    i = 1
  }
  while i < chars.length() {
    let c = chars[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
    }
    i = i + 1
  }
  if is_negative {
    -result
  } else {
    result
  }
}

///|
/// Parse a comma-separated list, trimming surrounding spaces per entry.
pub fn parse_comma_list(s : String) -> Array[String] {
  let result : Array[String] = []
  let current : Array[Char] = []
  for c in s {
    if c == ',' {
      let part = trim_ascii_spaces(String::from_array(current))
      if part.length() > 0 {
        result.push(part)
      }
      current.clear()
    } else {
      current.push(c)
    }
  }
  let last = trim_ascii_spaces(String::from_array(current))
  if last.length() > 0 {
    result.push(last)
  }
  result
}

///|
/// Strip leading and trailing ASCII whitespace from a string.
pub fn trim_ascii_spaces(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end &&
        (
          chars[start] == ' ' ||
          chars[start] == '\t' ||
          chars[start] == '\n' ||
          chars[start] == '\r'
        ) {
    start = start + 1
  }
  while end > start &&
        (
          chars[end - 1] == ' ' ||
          chars[end - 1] == '\t' ||
          chars[end - 1] == '\n' ||
          chars[end - 1] == '\r'
        ) {
    end = end - 1
  }
  if start == 0 && end == chars.length() {
    return s
  }
  let result : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

// === Path utilities (SoT for CLI commands) ===

///|
/// Extract directory name (last component) from path.
/// Example: "/foo/bar/baz" -> "baz", "pkg" -> "pkg"
pub fn extract_dirname(path : String) -> String {
  let clean = @pipeline.trim_trailing_slash(path)
  let chars = clean.to_array()
  let mut last_sep = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last_sep = i
    }
  }
  if last_sep < 0 {
    clean
  } else {
    let result : Array[Char] = []
    for i = last_sep + 1; i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  }
}

///|
/// Convert absolute path to relative path from base directory.
/// Example: make_relative_path("/foo/bar/x.ts", "/foo/bar") -> "x.ts"
pub fn make_relative_path(path : String, base : String) -> String {
  let clean_base = @pipeline.trim_trailing_slash(base)
  let prefix = clean_base + "/"
  if path.has_prefix(prefix) {
    let chars = path.to_array()
    let result : Array[Char] = []
    for i = prefix.length(); i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    path
  }
}

///|
/// Split display_name at ':' into (prefix, relative).
/// Example: "pkg1:auth/client.ts" -> ("pkg1", "auth/client.ts")
/// If no ':', returns ("", display_name).
pub fn split_display_name(display_name : String) -> (String, String) {
  let chars = display_name.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == ':' {
      return (
        substring(display_name, 0, i),
        substring(display_name, i + 1, chars.length()),
      )
    }
  }
  ("", display_name)
}

///|
/// Extract dirname prefix from display_name (before ':').
pub fn get_dirname_prefix(display_name : String) -> String {
  split_display_name(display_name).0
}

///|
/// Get relative part from display_name (after ':').
pub fn get_relative_part(display_name : String) -> String {
  split_display_name(display_name).1
}

///|
/// Split string by a single character delimiter.
/// Example: split_by_char("a,b,c", ',') -> ["a", "b", "c"]
pub fn split_by_char(s : String, delim : Char) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  for c in s {
    if c == delim {
      if buf.to_string().length() > 0 {
        parts.push(buf.to_string())
        buf.reset()
      }
    } else {
      buf.write_char(c)
    }
  }
  if buf.to_string().length() > 0 {
    parts.push(buf.to_string())
  }
  parts
}

///|
/// Split path by slash separator.
/// Example: "foo/bar/baz" -> ["foo", "bar", "baz"]
pub fn split_by_slash(path : String) -> Array[String] {
  let parts : Array[String] = []
  let chars = path.to_array()
  let current : Array[Char] = []
  for c in chars {
    if c == '/' || c == '\\' {
      if current.length() > 0 {
        parts.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(c)
    }
  }
  if current.length() > 0 {
    parts.push(String::from_array(current))
  }
  parts
}

///|
/// Extract unique display names for directories.
/// If all end with same name (e.g., "src"), use parent directory name.
/// Returns array of names in same order as input dirs.

///|
/// Return elapsed milliseconds since start timestamp.
pub fn elapsed_ms(start_ms : UInt64) -> UInt64 {
  let now = @env.now()
  if now >= start_ms {
    now - start_ms
  } else {
    0UL
  }
}

///|
/// Get parent directory of a path.
/// Example: parent_dir("/foo/bar/baz") -> "/foo/bar", parent_dir("foo") -> "."
pub fn parent_dir(path : String) -> String {
  let clean = @pipeline.trim_trailing_slash(path)
  let parts = split_by_slash(clean)
  if parts.length() <= 1 {
    return if path.has_prefix("/") { "/" } else { "." }
  }
  let buf = StringBuilder::new()
  if path.has_prefix("/") {
    buf.write_string("/")
  }
  for i in 0..<(parts.length() - 1) {
    if i > 0 {
      buf.write_string("/")
    }
    buf.write_string(parts[i])
  }
  buf.to_string()
}

///|
/// Return target dir and all ancestor directories up to filesystem root.
pub fn ancestor_dirs(dir : String) -> Array[String] {
  let result : Array[String] = [dir]
  let mut current = dir
  while true {
    let parent = parent_dir(current)
    if parent == current {
      break
    }
    result.push(parent)
    current = parent
  }
  result
}

///|
/// Extract unique display names for directories.
/// If all end with same name (e.g., "src"), use parent directory name.
/// Returns array of names in same order as input dirs.
pub fn extract_unique_dir_names(dirs : Array[String]) -> Array[String] {
  let base_names : Array[String] = []
  for dir in dirs {
    base_names.push(extract_dirname(dir))
  }
  // Check if all base names are the same
  let mut all_same = true
  if base_names.length() > 1 {
    let first = base_names[0]
    for i = 1; i < base_names.length(); i = i + 1 {
      if base_names[i] != first {
        all_same = false
        break
      }
    }
  } else {
    all_same = false
  }
  // If all same, use parent directory name
  if all_same {
    let names : Array[String] = []
    for dir in dirs {
      let clean = @pipeline.trim_trailing_slash(dir)
      let parts = split_by_slash(clean)
      if parts.length() >= 2 {
        names.push(parts[parts.length() - 2])
      } else if parts.length() == 1 {
        names.push(parts[0])
      } else {
        names.push(dir)
      }
    }
    names
  } else {
    base_names
  }
}

///|
/// Split text into lines by newline characters.
/// Handles both \n and \r\n line endings.
pub fn split_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  let current : Array[Char] = []
  for c in text {
    if c == '\n' {
      lines.push(String::from_array(current))
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
/// Format a double (0.0-1.0) as a percentage string.
/// Example: format_percent(0.75) -> "75%"
pub fn format_percent(d : Double) -> String {
  let percent = (d * 100.0).to_int()
  percent.to_string() + "%"
}

///|
/// Collect files from one or more directories using pipeline.discover_files (SoT).
/// Returns Array[(display_name, content)].
///
/// - For a single directory: display_name is the relative path.
/// - For multiple directories: display_name is "dirname:relative_path".
/// - Optional extensions filter (e.g. [".mbt", ".ts"]).
pub fn collect_files(
  dirs : Array[String],
  includes? : Array[String] = [],
  excludes? : Array[String] = [],
  extensions? : Array[String] = [],
  registry? : @registry.KGFRegistry? = None,
) -> Array[(String, String)] {
  let files : Array[(String, String)] = []
  let multi_dir = dirs.length() > 1
  let dir_names = extract_unique_dir_names(dirs)
  for i, dir in dirs {
    let opts = @pipeline.DiscoverOptions::new(
      includes~,
      excludes~,
      root_dir=dir,
    )
    let paths = @pipeline.discover_files([dir], opts)
    let dirname = dir_names[i]
    for path in paths {
      // Check extension filter
      if extensions.length() > 0 {
        let basename = @pipeline.extract_basename(path)
        let mut matched = false
        for ext in extensions {
          if basename.has_suffix(ext) {
            matched = true
            break
          }
        }
        if !matched {
          continue
        }
      }
      // Archive expansion: if registry is available and file is an archive,
      // expand it via VFS and emit inner entries instead.
      if try_expand_archive(
        path, dir, dirname, multi_dir, registry, files,
      ) {
        continue
      }
      try {
        let content = @fs.read_file_to_string(path)
        let relative = make_relative_path(path, dir)
        let display_name = if multi_dir {
          dirname + ":" + relative
        } else {
          relative
        }
        files.push((display_name, content))
      } catch {
        _ => ()
      }
    }
  }
  files
}

///|
/// Try to expand an archive file via VFS. Returns true if the file was
/// an archive and was expanded (or failed to expand), false if it's a
/// regular file that should be handled normally.
fn try_expand_archive(
  path : String,
  dir : String,
  dirname : String,
  multi_dir : Bool,
  registry : @registry.KGFRegistry?,
  files : Array[(String, String)],
) -> Bool {
  let reg = match registry {
    Some(r) => r
    None => return false
  }
  let language = match reg.detect_from_path(path) {
    Some(v) => v
    None => return false
  }
  let spec = match reg.get_spec(language) {
    Some(v) => v
    None => return false
  }
  if !@vfs.is_archive_spec(spec) {
    return false
  }
  // This is an archive — expand it
  let archive_spec = @vfs.ArchiveSpec::from_spec(spec)
  let vfs_entries = @vfs.expand_archive(path, archive_spec) catch {
    _ => return true // Failed to expand, skip
  }
  for entry in vfs_entries {
    if entry.is_binary {
      continue // Skip binary entries for text-based comparison
    }
    let relative = make_relative_path(entry.virtual_path, dir)
    let display_name = if multi_dir {
      dirname + ":" + relative
    } else {
      relative
    }
    files.push((display_name, entry.content))
  }
  true
}

///|
/// Truncate string to max length, appending ".." if truncated.
pub fn truncate(s : String, max_len : Int) -> String {
  let chars = s.to_array()
  if chars.length() <= max_len {
    return s
  }
  let result : Array[Char] = []
  for i = 0; i < max_len - 2; i = i + 1 {
    result.push(chars[i])
  }
  result.push('.')
  result.push('.')
  String::from_array(result)
}

///|
/// Extract substring from start (inclusive) to end (exclusive).
pub fn substring(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let actual_end = if end > chars.length() { chars.length() } else { end }
  let result : Array[Char] = []
  for i = start; i < actual_end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Normalize path by removing trailing slash.
/// Delegates to @pipeline.trim_trailing_slash (SoT).
pub fn normalize_path(path : String) -> String {
  @pipeline.trim_trailing_slash(path)
}

///|
/// Check if path is a directory.
pub fn is_directory(path : String) -> Bool {
  @fs.is_dir(path) catch {
    _ => false
  }
}

///|
/// Find the character position after a JSON key pattern `"key":` in a string.
/// Returns -1 if not found.
fn find_json_key_position(chars : Array[Char], key : String) -> Int {
  let pattern = "\"" + key + "\":"
  let pat_chars = pattern.to_array()
  for i = 0; i < chars.length() - pat_chars.length(); i = i + 1 {
    let mut found = true
    for j = 0; j < pat_chars.length(); j = j + 1 {
      if chars[i + j] != pat_chars[j] {
        found = false
        break
      }
    }
    if found {
      return i + pat_chars.length()
    }
  }
  -1
}

///|
/// Extract a string value from a JSON-like text by key.
/// Simple pattern-based extraction (no full JSON parser).
pub fn extract_json_string(json : String, key : String) -> String {
  let chars = json.to_array()
  let mut start = find_json_key_position(chars, key)
  if start < 0 {
    return ""
  }
  while start < chars.length() && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  if start >= chars.length() || chars[start] != '"' {
    return ""
  }
  start = start + 1
  let result : Array[Char] = []
  while start < chars.length() && chars[start] != '"' {
    if chars[start] == '\\' && start + 1 < chars.length() {
      start = start + 1
    }
    result.push(chars[start])
    start = start + 1
  }
  String::from_array(result)
}

///|
/// Extract a string array from a JSON-like text by key.
/// Simple pattern-based extraction (no full JSON parser).
pub fn extract_json_array(json : String, key : String) -> Array[String] {
  let result : Array[String] = []
  let chars = json.to_array()
  let mut start = find_json_key_position(chars, key)
  if start < 0 {
    return result
  }
  while start < chars.length() && chars[start] != '[' {
    start = start + 1
  }
  if start >= chars.length() {
    return result
  }
  start = start + 1
  while start < chars.length() && chars[start] != ']' {
    while start < chars.length() &&
          (
            chars[start] == ' ' ||
            chars[start] == '\t' ||
            chars[start] == '\n' ||
            chars[start] == ','
          ) {
      start = start + 1
    }
    if start >= chars.length() || chars[start] == ']' {
      break
    }
    if chars[start] == '"' {
      start = start + 1
      let item : Array[Char] = []
      while start < chars.length() && chars[start] != '"' {
        item.push(chars[start])
        start = start + 1
      }
      if item.length() > 0 {
        result.push(String::from_array(item))
      }
      start = start + 1
    } else {
      start = start + 1
    }
  }
  result
}

///|
/// Join lines with newline separator.
pub fn join_lines(lines : Array[String]) -> String {
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
/// Render a markdown inline code list with label.
/// Writes "- **label**: `item1`, `item2`\n" to the buffer.
pub fn render_inline_code_list(
  buf : StringBuilder,
  label : String,
  items : Array[String],
) -> Unit {
  if items.length() == 0 {
    return
  }
  buf.write_string("- **" + label + "**: ")
  for i, item in items {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string("`" + item + "`")
  }
  buf.write_string("\n")
}

///|
/// Write content to a file or stdout.
/// If output is empty or "-", prints to stdout.
/// Otherwise, ensures parent directory exists and writes to file.
pub fn write_output(
  output : String,
  content : String,
  label? : String = "Output",
) -> Unit {
  if output.length() == 0 || output == "-" {
    println(content)
    return
  }
  @config_paths.ensure_parent_dir(output)
  @fs.write_string_to_file(output, content) catch {
    e => {
      println("Error writing file: " + e.to_string())
      return
    }
  }
  println(label + " written to: " + output)
}

///|
/// Slugify text for URL-safe identifiers.
/// Lowercases, replaces spaces/slashes/underscores/dots with hyphens.
pub fn slugify(text : String) -> String {
  let buf = StringBuilder::new()
  for c in text {
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' {
      buf.write_char(c)
    } else if c >= 'A' && c <= 'Z' {
      buf.write_char((c.to_int() + 32).unsafe_to_char())
    } else if c == ' ' || c == '/' || c == '_' || c == '.' {
      buf.write_char('-')
    }
  }
  buf.to_string()
}

///|
/// Make a URL anchor from heading text.
/// Like slugify but only accepts spaces as separators.
pub fn make_anchor(text : String) -> String {
  let buf = StringBuilder::new()
  for c in text {
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' {
      buf.write_char(c)
    } else if c >= 'A' && c <= 'Z' {
      buf.write_char((c.to_int() + 32).unsafe_to_char())
    } else if c == ' ' {
      buf.write_char('-')
    }
  }
  buf.to_string()
}

///|
/// Capitalize the first character of a string.
pub fn capitalize(text : String) -> String {
  if text.length() == 0 {
    return text
  }
  let chars = text.to_array()
  if chars[0] >= 'a' && chars[0] <= 'z' {
    let buf = StringBuilder::new()
    buf.write_char((chars[0].to_int() - 32).unsafe_to_char())
    for i = 1; i < chars.length(); i = i + 1 {
      buf.write_char(chars[i])
    }
    buf.to_string()
  } else {
    text
  }
}

///|
/// Extract the first sentence (up to first '.' or newline).
pub fn first_sentence(text : String) -> String {
  let mut idx = 0
  for c in text {
    if c == '.' || c == '\n' {
      return substring(text, 0, idx)
    }
    idx = idx + 1
  }
  if text.length() > 100 {
    truncate(text, 100)
  } else {
    text
  }
}

///|
/// Count the number of lines in text.
pub fn count_lines(text : String) -> Int {
  split_lines(text).length()
}

///|
/// Resolve a wiki directory path.
/// If `wiki_dir` is the default ".indexion/wiki", walks up from `base_dir`
/// to find the project root and returns `<root>/.indexion/wiki`.
/// Returns None if the project root cannot be found.
pub fn resolve_wiki_dir(
  wiki_dir : String,
  base_dir~ : String = ".",
) -> String? {
  if wiki_dir == ".indexion/wiki" {
    @config_paths.resolve_project_indexion_dir(base_dir, "wiki")
  } else {
    Some(wiki_dir)
  }
}

///|
/// Get a string option value from CLI matches, with a default fallback.
pub fn get_option(
  matches : @argparse.Matches,
  key : String,
  default : String,
) -> String {
  match matches.values.get(key) {
    Some(arr) => if arr.length() > 0 { arr[0] } else { default }
    _ => default
  }
}

///|
/// Get a flag (boolean) value from CLI matches.
pub fn get_flag(matches : @argparse.Matches, key : String) -> Bool {
  match matches.flags.get(key) {
    Some(v) => v
    _ => false
  }
}
