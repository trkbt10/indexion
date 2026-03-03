///|
/// Parses resolver block into normalized ResolverSpec.
/// Supports YAML-like syntax with aliases.
pub fn parse_resolver(text : String) -> @types.ResolverSpec {
  let lines = split_lines(text)
  let kv : Map[String, String] = {}
  let aliases : Array[@types.ResolverAlias] = []
  let mut i = 0
  while i < lines.length() {
    let raw = lines[i]
    let ln = trim_str(raw)
    // Skip empty lines and comments
    if ln.length() == 0 || starts_with(ln, "#") {
      i += 1
      continue
    }
    // Check for aliases block
    if starts_with(ln, "aliases:") {
      i += 1
      i = parse_aliases_block(lines, i, aliases)
      continue
    }
    // Parse key: value
    match parse_kv_line(ln) {
      Some((k, v)) => kv.set(k, v)
      None => ()
    }
    i += 1
  }
  build_resolver_spec(kv, aliases)
}

///|
/// Parses a key: value line.
fn parse_kv_line(line : String) -> (String, String)? {
  let colon_pos = find_char(line, 0, ':')
  guard colon_pos > 0 else { return None }
  let key = trim_str(substr(line, 0, colon_pos))
  let value = trim_str(substr_from(line, colon_pos + 1))
  Some((key, value))
}

///|
/// Parses the aliases block (indented list items).
fn parse_aliases_block(
  lines : Array[String],
  start : Int,
  aliases : Array[@types.ResolverAlias],
) -> Int {
  let mut i = start
  while i < lines.length() {
    let li = lines[i]
    // Check if still in indented block
    if not(is_indented(li)) {
      break
    }
    let sub = trim_str(li)
    // Look for list item marker
    if starts_with(sub, "-") {
      i += 1
      let (alias_entry, next_i) = parse_single_alias(lines, i)
      match alias_entry {
        Some(a) => aliases.push(a)
        None => ()
      }
      i = next_i
    } else {
      i += 1
    }
  }
  i
}

///|
/// Checks if a line is indented (starts with space or tab).
fn is_indented(line : String) -> Bool {
  if line.length() == 0 {
    return false
  }
  let first = char_at(line, 0)
  first == ' ' || first == '\t'
}

///|
/// Checks if a line is double-indented (4 spaces or 2 tabs).
fn is_double_indented(line : String) -> Bool {
  if line.length() < 2 {
    return false
  }
  starts_with(line, "    ") || starts_with(line, "\t\t")
}

///|
/// Parses a single alias entry (pattern/replace fields).
fn parse_single_alias(
  lines : Array[String],
  start : Int,
) -> (@types.ResolverAlias?, Int) {
  let mut pattern = ""
  let mut replace = ""
  let mut i = start
  while i < lines.length() {
    let s = lines[i]
    // Must be double-indented
    if not(is_double_indented(s)) {
      break
    }
    let t = trim_str(s)
    match parse_kv_line(t) {
      Some((key, val)) =>
        if key == "pattern" {
          pattern = val
        } else if key == "replace" {
          replace = val
        }
      None => ()
    }
    i += 1
  }
  if pattern.length() > 0 || replace.length() > 0 {
    (Some(@types.ResolverAlias::new(pattern, replace)), i)
  } else {
    (None, i)
  }
}

///|
/// Builds the ResolverSpec from parsed key-value pairs and aliases.
fn build_resolver_spec(
  kv : Map[String, String],
  aliases : Array[@types.ResolverAlias],
) -> @types.ResolverSpec {
  let sources = get_list(kv, "sources")
  let relative_prefixes = get_list(kv, "relative_prefixes")
  let exts = get_list(kv, "exts")
  let indexes = get_list(kv, "indexes")
  let bare_prefix = get_string(kv, "bare_prefix")
  let module_path_style = get_module_path_style(kv.get("module_path_style"))
  let ns_prefix = get_optional_string(kv, "ns_prefix")
  let ns_segments = get_int(kv, "ns_segments", default=2)
  let rust_mod_mode = get_bool(kv, "rust_mod_mode")
  let cargo_auto_from_roots = get_list(kv, "cargo_auto_from_roots")
  @types.ResolverSpec::new(
    sources~,
    relative_prefixes~,
    exts~,
    indexes~,
    bare_prefix~,
    module_path_style~,
    aliases~,
    ns_prefix~,
    ns_segments~,
    rust_mod_mode~,
    cargo_auto_from_roots~,
  )
}

///|
/// Gets a list value from the key-value map.
fn get_list(kv : Map[String, String], key : String) -> Array[String] {
  match kv.get(key) {
    Some(v) => parse_list(v)
    None => []
  }
}

///|
/// Gets a string value from the key-value map.
fn get_string(kv : Map[String, String], key : String) -> String {
  match kv.get(key) {
    Some(v) => v
    None => ""
  }
}

///|
/// Gets an optional string value from the key-value map.
fn get_optional_string(kv : Map[String, String], key : String) -> String? {
  match kv.get(key) {
    Some(v) => if v.length() > 0 { Some(v) } else { None }
    None => None
  }
}

///|
/// Gets an integer value from the key-value map.
fn get_int(kv : Map[String, String], key : String, default~ : Int) -> Int {
  match kv.get(key) {
    Some(v) => parse_int_str(v, default)
    None => default
  }
}

///|
/// Gets a boolean value from the key-value map.
fn get_bool(kv : Map[String, String], key : String) -> Bool {
  match kv.get(key) {
    Some(v) => trim_str(v) == "true"
    None => false
  }
}

///|
/// Gets a default ModulePathStyle (slash).
fn default_module_path_style() -> @types.ModulePathStyle {
  @types.ModulePathStyle::from_string("slash").unwrap()
}

///|
/// Parses a string to ModulePathStyle.
fn get_module_path_style(s : String?) -> @types.ModulePathStyle {
  match s {
    Some(v) =>
      match @types.ModulePathStyle::from_string(v) {
        Some(style) => style
        None => default_module_path_style()
      }
    None => default_module_path_style()
  }
}

///|
/// Parses a string to an integer.
fn parse_int_str(s : String, default : Int) -> Int {
  let trimmed = trim_str(s)
  if trimmed.length() == 0 {
    return default
  }
  let arr = trimmed.to_array()
  let mut result = 0
  let mut is_negative = false
  let mut start = 0
  if arr[0] == '-' {
    is_negative = true
    start = 1
  } else if arr[0] == '+' {
    start = 1
  }
  for i in start..<arr.length() {
    let c = arr[i]
    if is_digit(c) {
      result = result * 10 + (c.to_int() - '0'.to_int())
    } else {
      return default
    }
  }
  if is_negative {
    -result
  } else {
    result
  }
}
