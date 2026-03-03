///|
/// Parses rule lines into rule name to expression mapping.
/// Preserves newlines between indented lines.
/// Syntax:
///   Name -> expression
///           continued on multiple lines
pub fn parse_rules(text : String) -> Map[String, @types.RuleDef] {
  let lines = split_lines(text)
  let rules : Map[String, @types.RuleDef] = {}
  let mut current_name : String? = None
  let buf : Array[String] = []
  for line in lines {
    let ln = trim_str(line)
    // Skip empty lines and comments, but preserve newlines in buffer
    if ln.length() == 0 || starts_with(ln, "#") {
      if current_name is Some(_) {
        buf.push("")
      }
      continue
    }
    // Try to match a new rule definition: Name -> expr
    match parse_rule_header(line) {
      Some((name, expr)) => {
        // Save previous rule if any
        match current_name {
          Some(prev_name) => {
            let full_expr = join_rule_buffer(buf)
            rules.set(prev_name, @types.RuleDef::new(prev_name, full_expr))
          }
          None => ()
        }
        // Start new rule
        current_name = Some(name)
        buf.clear()
        buf.push(expr)
      }
      None =>
        // Continuation line
        if current_name is Some(_) {
          buf.push(ln)
        }
    }
  }
  // Save last rule
  match current_name {
    Some(name) => {
      let full_expr = join_rule_buffer(buf)
      rules.set(name, @types.RuleDef::new(name, full_expr))
    }
    None => ()
  }
  rules
}

///|
/// Tries to parse a rule header: Name -> expression
fn parse_rule_header(line : String) -> (String, String)? {
  // Check if line starts with identifier (not indented)
  if line.length() == 0 {
    return None
  }
  let first = char_at(line, 0)
  if is_whitespace(first) {
    return None
  }
  // Read identifier
  let (name, after_name) = read_identifier(line, 0)
  guard name.length() > 0 else { return None }
  // Skip whitespace
  let arrow_pos = skip_whitespace(line, after_name)
  // Check for ->
  guard arrow_pos + 1 < line.length() else { return None }
  guard char_at(line, arrow_pos) == '-' && char_at(line, arrow_pos + 1) == '>' else {
    return None
  }
  // Get expression after ->
  let expr_start = skip_whitespace(line, arrow_pos + 2)
  let expr = if expr_start < line.length() {
    substr_from(line, expr_start)
  } else {
    ""
  }
  Some((name, expr))
}

///|
/// Joins buffer lines into a single expression, preserving newlines.
fn join_rule_buffer(buf : Array[String]) -> String {
  let result = StringBuilder::new()
  for i, line in buf {
    if i > 0 {
      result.write_char('\n')
    }
    result.write_string(line)
  }
  trim_str(result.to_string())
}
