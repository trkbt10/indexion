///|
/// YAML frontmatter emission for OKF concept documents.
///
/// OKF consumers parse frontmatter as YAML, so scalars that would change
/// meaning in plain style (indicators, flow characters, leading/trailing
/// whitespace) are emitted double-quoted with escapes. There is no YAML
/// serializer elsewhere in the codebase; this is the SoT for emitting it.

///|
/// A frontmatter value: scalar string or flow-style list of strings.
pub(all) enum OkfValue {
  Str(String)
  List(Array[String])
}

///|
/// Render a YAML frontmatter block, including both `---` fences and a
/// trailing newline after the closing fence.
pub fn render_frontmatter(entries : Array[(String, OkfValue)]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("---\n")
  for entry in entries {
    let (key, value) = entry
    buf.write_string(key)
    buf.write_string(": ")
    match value {
      Str(s) => buf.write_string(yaml_scalar(s))
      List(items) => {
        buf.write_string("[")
        for i, item in items {
          if i > 0 {
            buf.write_string(", ")
          }
          buf.write_string(yaml_scalar(item))
        }
        buf.write_string("]")
      }
    }
    buf.write_string("\n")
  }
  buf.write_string("---\n")
  buf.to_string()
}

///|
/// Quote a scalar for YAML when plain style would be ambiguous;
/// otherwise emit it verbatim.
fn yaml_scalar(s : String) -> String {
  if !needs_quoting(s) {
    return s
  }
  let buf = StringBuilder::new()
  buf.write_string("\"")
  for ch in s.to_array() {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      _ => buf.write_char(ch)
    }
  }
  buf.write_string("\"")
  buf.to_string()
}

///|
/// Whether a scalar needs double-quoting to survive YAML plain-style parsing.
/// Also quotes values YAML would coerce to non-string types (booleans,
/// nulls, and number-looking scalars).
fn needs_quoting(s : String) -> Bool {
  let chars = s.to_array()
  if chars.length() == 0 {
    return true
  }
  if is_yaml_coercible(s) {
    return true
  }
  let first = chars[0]
  if first == '-' ||
    first == '?' ||
    first == ' ' ||
    first == '.' ||
    first == '+' ||
    first == '~' ||
    (first >= '0' && first <= '9') {
    return true
  }
  if chars[chars.length() - 1] == ' ' {
    return true
  }
  for ch in chars {
    if ch == ':' ||
      ch == '#' ||
      ch == '[' ||
      ch == ']' ||
      ch == '{' ||
      ch == '}' ||
      ch == ',' ||
      ch == '"' ||
      ch == '\'' ||
      ch == '\n' ||
      ch == '\t' ||
      ch == '\r' ||
      ch == '&' ||
      ch == '*' ||
      ch == '!' ||
      ch == '|' ||
      ch == '>' ||
      ch == '%' ||
      ch == '@' ||
      ch == '`' {
      return true
    }
  }
  false
}

///|
/// Keywords YAML parses as booleans or null in plain style (any casing).
fn is_yaml_coercible(s : String) -> Bool {
  let lowered = StringBuilder::new()
  for ch in s.to_array() {
    if ch >= 'A' && ch <= 'Z' {
      lowered.write_char((ch.to_int() + 32).unsafe_to_char())
    } else {
      lowered.write_char(ch)
    }
  }
  let value = lowered.to_string()
  value == "true" ||
  value == "false" ||
  value == "null" ||
  value == "yes" ||
  value == "no" ||
  value == "on" ||
  value == "off"
}
