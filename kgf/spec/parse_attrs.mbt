///|
/// Parses simple one-line attribute actions per rule into structured form.
/// Syntax:
///   on RuleName: kind1 key1=val1; kind2; ...
pub fn parse_attrs(text : String) -> Map[String, Array[@types.AttrAction]] {
  let result : Map[String, Array[@types.AttrAction]] = {}
  let lines = split_lines(text)
  for line in lines {
    let ln = trim_str(line)
    // Skip empty lines and comments
    if ln.length() == 0 || starts_with(ln, "#") {
      continue
    }
    // Look for "on RuleName: actions"
    if starts_with(ln, "on ") {
      match parse_attr_line(ln) {
        Some((rule, actions)) => result.set(rule, actions)
        None => ()
      }
    }
  }
  result
}

///|
/// Parses a single attribute line: on RuleName: kind1 key1=val1; kind2; ...
fn parse_attr_line(line : String) -> (String, Array[@types.AttrAction])? {
  // Skip "on "
  let after_on = skip_whitespace(line, 3)
  // Read rule name
  let (rule, after_rule) = read_identifier(line, after_on)
  guard rule.length() > 0 else { return None }
  // Skip whitespace and find colon
  let colon_pos = skip_whitespace(line, after_rule)
  guard colon_pos < line.length() && char_at(line, colon_pos) == ':' else {
    return None
  }
  // Get actions string after colon
  let actions_str = trim_str(substr_from(line, colon_pos + 1))
  // Parse actions separated by semicolon
  let actions = parse_action_list(actions_str)
  Some((rule, actions))
}

///|
/// Parses a list of actions separated by semicolons.
fn parse_action_list(text : String) -> Array[@types.AttrAction] {
  let result : Array[@types.AttrAction] = []
  let parts = split_by_char(text, ';')
  for part in parts {
    let trimmed = trim_str(part)
    if trimmed.length() > 0 {
      result.push(parse_single_action(trimmed))
    }
  }
  result
}

///|
/// Splits text by a character.
fn split_by_char(text : String, delim : Char) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for c in text {
    if c == delim {
      result.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  result.push(buf.to_string())
  result
}

///|
/// Parses a single action: kind key1=val1 key2=val2 ...
fn parse_single_action(text : String) -> @types.AttrAction {
  let parts = split_by_space(text)
  guard parts.length() > 0 else { return @types.AttrAction::new("") }
  let kind = parts[0]
  let params : Map[String, String] = {}
  for i in 1..<parts.length() {
    let kv = parts[i]
    match parse_key_value(kv) {
      Some((k, v)) => params.set(k, v)
      None => ()
    }
  }
  @types.AttrAction::new(kind, params~)
}

///|
/// Splits text by whitespace.
fn split_by_space(text : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for c in text {
    if is_whitespace(c) {
      let part = buf.to_string()
      if part.length() > 0 {
        result.push(part)
      }
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  let part = buf.to_string()
  if part.length() > 0 {
    result.push(part)
  }
  result
}

///|
/// Parses a key=value pair.
fn parse_key_value(text : String) -> (String, String)? {
  let eq_pos = find_char(text, 0, '=')
  guard eq_pos > 0 else { return None }
  let key = substr(text, 0, eq_pos)
  let value = substr_from(text, eq_pos + 1)
  Some((key, value))
}
