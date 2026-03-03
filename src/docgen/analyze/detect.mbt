// File content detection and KGF spec selection.

///|
/// Extract file extension from path (without dot).
pub fn extract_extension(path : String) -> String {
  let chars = path.to_array()
  let mut last_dot = -1
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '.' {
      last_dot = i
    } else if chars[i] == '/' || chars[i] == '\\' {
      last_slash = i
    }
  }
  // Extension must be after the last slash
  if last_dot > last_slash && last_dot < chars.length() - 1 {
    let result : Array[Char] = []
    for i = last_dot + 1; i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    ""
  }
}

///|
/// Detect language from file extension.
fn detect_from_extension(ext : String) -> DetectedLang {
  match ext {
    "ts" | "tsx" | "mts" | "cts" => DetectedLang::TypeScript
    "js" | "jsx" | "mjs" | "cjs" => DetectedLang::JavaScript
    "py" | "pyi" => DetectedLang::Python
    "mbt" => DetectedLang::MoonBit
    "go" => DetectedLang::Go
    "rs" => DetectedLang::Rust
    "md" | "markdown" => DetectedLang::Markdown
    "html" | "htm" => DetectedLang::Html
    "css" | "scss" | "sass" => DetectedLang::Css
    "sql" => DetectedLang::Sql
    "json" => DetectedLang::Json
    "yaml" | "yml" => DetectedLang::Yaml
    _ => DetectedLang::Unknown
  }
}

///|
/// Check if content looks like TypeScript/JavaScript.
fn looks_like_typescript(content : String) -> Bool {
  // Check for common TS/JS patterns
  has_pattern(content, "import ") ||
  has_pattern(content, "export ") ||
  has_pattern(content, "function ") ||
  has_pattern(content, "const ") ||
  has_pattern(content, "class ") ||
  has_pattern(content, "interface ") ||
  has_pattern(content, "type ") ||
  has_pattern(content, "=> {")
}

///|
/// Check if content looks like Python.
fn looks_like_python(content : String) -> Bool {
  has_pattern(content, "def ") ||
  has_pattern(content, "class ") ||
  has_pattern(content, "import ") ||
  has_pattern(content, "from ") ||
  has_pattern(content, "if __name__") ||
  has_pattern(content, "\"\"\"")
}

///|
/// Check if content looks like MoonBit.
fn looks_like_moonbit(content : String) -> Bool {
  has_pattern(content, "fn ") ||
  has_pattern(content, "pub fn ") ||
  has_pattern(content, "struct ") ||
  has_pattern(content, "enum ") ||
  has_pattern(content, "///|") ||
  has_pattern(content, "derive(")
}

///|
/// Check if content looks like Go.
fn looks_like_go(content : String) -> Bool {
  has_pattern(content, "package ") ||
  has_pattern(content, "func ") ||
  (has_pattern(content, "type ") && has_pattern(content, " struct {")) ||
  has_pattern(content, "import (")
}

///|
/// Check if content looks like Rust.
fn looks_like_rust(content : String) -> Bool {
  (has_pattern(content, "fn ") && has_pattern(content, "-> ")) ||
  has_pattern(content, "impl ") ||
  has_pattern(content, "use ") ||
  has_pattern(content, "mod ") ||
  has_pattern(content, "pub fn ") ||
  has_pattern(content, "#[")
}

///|
/// Check if content looks like HTML.
fn looks_like_html(content : String) -> Bool {
  has_pattern(content, "<!DOCTYPE") ||
  has_pattern(content, "<html") ||
  has_pattern(content, "<head") ||
  has_pattern(content, "<body")
}

///|
/// Check if content looks like CSS.
fn looks_like_css(content : String) -> Bool {
  has_pattern(content, "{") &&
  (
    has_pattern(content, "color:") ||
    has_pattern(content, "background:") ||
    has_pattern(content, "margin:") ||
    has_pattern(content, "padding:") ||
    has_pattern(content, "display:")
  )
}

///|
/// Check if content looks like Markdown.
fn looks_like_markdown(content : String) -> Bool {
  has_pattern(content, "# ") ||
  has_pattern(content, "## ") ||
  has_pattern(content, "```") ||
  (has_pattern(content, "- ") && has_pattern(content, "\n- "))
}

///|
/// Check if content looks like SQL.
fn looks_like_sql(content : String) -> Bool {
  let upper = to_upper(content)
  has_pattern(upper, "SELECT ") ||
  has_pattern(upper, "CREATE TABLE") ||
  has_pattern(upper, "INSERT INTO") ||
  has_pattern(upper, "UPDATE ") ||
  has_pattern(upper, "DELETE FROM")
}

///|
/// Detect language from file content.
fn detect_from_content(content : String) -> DetectedLang {
  // Check each language pattern
  if looks_like_moonbit(content) {
    return DetectedLang::MoonBit
  }
  if looks_like_rust(content) {
    return DetectedLang::Rust
  }
  if looks_like_go(content) {
    return DetectedLang::Go
  }
  if looks_like_python(content) {
    return DetectedLang::Python
  }
  if looks_like_typescript(content) {
    return DetectedLang::TypeScript
  }
  if looks_like_html(content) {
    return DetectedLang::Html
  }
  if looks_like_css(content) {
    return DetectedLang::Css
  }
  if looks_like_markdown(content) {
    return DetectedLang::Markdown
  }
  if looks_like_sql(content) {
    return DetectedLang::Sql
  }
  DetectedLang::Unknown
}

///|
/// Detect file language using both extension and content analysis.
pub fn detect_language(path : String, content : String) -> DetectedLang {
  let ext = extract_extension(path)
  let from_ext = detect_from_extension(ext)
  // If extension gives a definite answer, use it
  if from_ext != DetectedLang::Unknown {
    return from_ext
  }
  // Otherwise, analyze content
  detect_from_content(content)
}

///|
/// Analyze a file and return FileInfo with spec selection.
pub fn analyze_file(path : String, content : String) -> FileInfo {
  let ext = extract_extension(path)
  let lang = detect_language(path, content)
  let spec_name = lang.doc_spec_name()
  FileInfo::new(path, lang, ext, spec_name)
}

///|
/// Check if string contains a pattern.
fn has_pattern(s : String, pattern : String) -> Bool {
  find_substring(s, pattern) >= 0
}

///|
/// Find substring index.
fn find_substring(s : String, pattern : String) -> Int {
  let s_chars = s.to_array()
  let p_chars = pattern.to_array()
  if p_chars.length() == 0 || s_chars.length() < p_chars.length() {
    return -1
  }
  for i = 0; i <= s_chars.length() - p_chars.length(); i = i + 1 {
    let mut found = true
    for j = 0; j < p_chars.length(); j = j + 1 {
      if s_chars[i + j] != p_chars[j] {
        found = false
        break
      }
    }
    if found {
      return i
    }
  }
  -1
}

///|
/// Convert string to uppercase (ASCII only).
fn to_upper(s : String) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  for c in chars {
    let code = c.to_int()
    if code >= 97 && code <= 122 {
      // a-z -> A-Z
      result.push(Char::from_int(code - 32))
    } else {
      result.push(c)
    }
  }
  String::from_array(result)
}
