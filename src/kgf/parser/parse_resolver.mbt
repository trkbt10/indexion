///|
/// # KGF Resolver Section Syntax
///
/// The `=== resolver` section configures module path resolution.
/// Uses YAML-like syntax for flexibility and readability.
///
/// ## EBNF Grammar
///
/// ```ebnf
/// ResolverSection ::= ( KeyValue | AliasesBlock | ResolveBlock )*
///
/// KeyValue     ::= Key ":" Value NL
/// Key          ::= "sources" | "relative_prefixes" | "exts" | "indexes"
///                | "bare_prefix" | "module_path_style" | "ns_prefix"
///                | "ns_segments"
/// Value        ::= STRING | List
/// List         ::= Value ( "," Value )*
///
/// AliasesBlock ::= "aliases:" NL AliasEntry+
/// AliasEntry   ::= INDENT "-" NL AliasFields
/// AliasFields  ::= INDENT2 "pattern:" REGEX NL INDENT2 "replace:" STRING NL
///
/// ResolveBlock ::= "resolve:" NL ResolveStep+
/// ResolveStep  ::= INDENT "-" StepSpec NL | INDENT "-" NL StepFields
/// StepSpec     ::= StepType ":" StepValue
/// StepType     ::= "manifest" | "marker" | "index" | "ext" | "sibling" | "fallback"
/// StepValue    ::= ManifestSpec | FileList | Prefix
/// ManifestSpec ::= FileName "@" Query ( "?" Condition )?
/// StepFields   ::= ( INDENT2 StepField NL )+
/// StepField    ::= "type:" StepType | "file:" FileName | "query:" Query
///                | "files:" FileList | "prefix:" Prefix | "when:" Condition
/// ```
///
/// ## Configuration Keys
///
/// | Key | Type | Description |
/// |-----|------|-------------|
/// | `sources` | list | Source file extensions (`.ts`, `.py`) |
/// | `relative_prefixes` | list | Prefixes for relative imports (`./`, `../`) |
/// | `exts` | list | Extensions to try when resolving |
/// | `indexes` | list | Index file names (`index.ts`) |
/// | `bare_prefix` | string | Prefix for bare module names (`npm:`) |
/// | `module_path_style` | enum | Path separator: `slash`, `dot`, `coloncol` |
/// | `ns_prefix` | string | Namespace prefix |
/// | `ns_segments` | int | Namespace segment count |
///
/// ## Resolve Step Types
///
/// | Type | Description | Value Format |
/// |------|-------------|--------------|
/// | `manifest` | Read from manifest file | `file @ query` |
/// | `marker` | Check marker file exists | file list |
/// | `index` | Try index files in directory | file list |
/// | `ext` | Try adding extensions | extension list |
/// | `sibling` | Try sibling file | file list |
/// | `fallback` | Apply fallback prefix | prefix string |
///
/// ## Examples
///
/// ```kgf
/// === resolver
/// # Basic configuration
/// sources: .ts, .tsx, .d.ts
/// relative_prefixes: ./, ../, /
/// module_path_style: slash
///
/// # Path aliases (e.g., @/components -> src/components)
/// aliases:
///   -
///     pattern: ^@/(.*)$
///     replace: src/\1
///   -
///     pattern: ^~/(.*)$
///     replace: lib/\1
///
/// # Resolution chain (tried in order)
/// resolve:
///   # Check package.json exports for types
///   -
///     type: manifest
///     file: package.json
///     query: exports["."].types
///     when: type
///   # Shorthand: manifest: file @ query
///   - manifest: package.json @ main | module
///   # Try index files
///   - index: /index.ts, /index.tsx, /index.js
///   # Try extensions
///   - ext: .ts, .tsx, .d.ts, .js
///   # Fallback to npm prefix
///   - fallback: npm:
/// ```

///|
/// Parses resolver block into normalized ResolverSpec.
/// Supports YAML-like syntax with aliases and resolve chain.
pub fn parse_resolver(text : String) -> @types.ResolverSpec {
  parse_resolver_with_sources(text, [])
}

///|
/// Parses resolver block with sources from header.
/// Header sources take precedence over resolver section sources.
pub fn parse_resolver_with_sources(
  text : String,
  header_sources : Array[String],
) -> @types.ResolverSpec {
  let lines = split_lines(text)
  let kv : Map[String, String] = {}
  let aliases : Array[@types.ResolverAlias] = []
  let resolve_chain : Array[@types.ResolveStep] = []
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
    // Check for resolve block
    if starts_with(ln, "resolve:") {
      i += 1
      i = parse_resolve_block(lines, i, resolve_chain)
      continue
    }
    // Parse key: value (skip 'sources' if header has it)
    match parse_kv_line(ln) {
      Some((k, v)) =>
        // Header sources take precedence
        if k == "sources" && header_sources.length() > 0 {
          () // Skip resolver section sources
        } else {
          kv.set(k, v)
        }
      None => ()
    }
    i += 1
  }
  build_resolver_spec_with_sources(kv, aliases, resolve_chain, header_sources)
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
/// Parses the resolve block (indented list items).
fn parse_resolve_block(
  lines : Array[String],
  start : Int,
  steps : Array[@types.ResolveStep],
) -> Int {
  let mut i = start
  while i < lines.length() {
    let li = lines[i]
    // Check if still in indented block
    if not(is_indented(li)) {
      break
    }
    let sub = trim_str(li)
    // Skip empty or comment lines
    if sub.length() == 0 || starts_with(sub, "#") {
      i += 1
      continue
    }
    // Look for list item marker
    if starts_with(sub, "-") {
      let after_dash = trim_str(substr_from(sub, 1))
      // Check if it's a single-line form: "- type: value"
      match parse_single_line_resolve_step(after_dash) {
        Some(step) => {
          steps.push(step)
          i += 1
        }
        None => {
          // Multi-line form: "-" followed by indented key-value pairs
          i += 1
          let (step, next_i) = parse_multi_line_resolve_step(lines, i)
          match step {
            Some(s) => steps.push(s)
            None => ()
          }
          i = next_i
        }
      }
    } else {
      i += 1
    }
  }
  i
}

///|
/// Parses a single-line resolve step: "type: value" or "type: v1, v2, v3"
fn parse_single_line_resolve_step(line : String) -> @types.ResolveStep? {
  // Format: "type: value" where type is manifest, marker, index, ext, sibling, fallback
  let colon_pos = find_char(line, 0, ':')
  guard colon_pos > 0 else { return None }
  let type_str = trim_str(substr(line, 0, colon_pos))
  let value = trim_str(substr_from(line, colon_pos + 1))
  match @types.ResolveStepType::from_string(type_str) {
    Some(@types.ResolveStepType::Manifest) => {
      // For manifest, we need more info, so it's not a single-line form
      // But we can support "manifest: package.json @ query" format
      let (file, query, when_cond) = parse_manifest_value(value)
      if file.length() > 0 {
        Some(
          @types.ResolveStep::manifest(file, query, when_condition=when_cond),
        )
      } else {
        None
      }
    }
    Some(@types.ResolveStepType::Marker) =>
      Some(@types.ResolveStep::marker(parse_list(value)))
    Some(@types.ResolveStepType::Index) =>
      Some(@types.ResolveStep::index(parse_list(value)))
    Some(@types.ResolveStepType::Ext) =>
      Some(@types.ResolveStep::ext(parse_list(value)))
    Some(@types.ResolveStepType::Sibling) =>
      Some(@types.ResolveStep::sibling(parse_list(value)))
    Some(@types.ResolveStepType::Fallback) =>
      Some(@types.ResolveStep::fallback(value))
    None => None
  }
}

///|
/// Parses manifest value: "file @ query ? condition" or "file @ query"
fn parse_manifest_value(value : String) -> (String, String, String) {
  let mut file = ""
  let mut query = ""
  let mut when_cond = ""
  // Check for condition: "file @ query ? condition"
  let question_pos = find_char(value, 0, '?')
  let value_without_cond = if question_pos >= 0 {
    when_cond = trim_str(substr_from(value, question_pos + 1))
    trim_str(substr(value, 0, question_pos))
  } else {
    value
  }
  // Check for query: "file @ query"
  let at_pos = find_char(value_without_cond, 0, '@')
  if at_pos >= 0 {
    file = trim_str(substr(value_without_cond, 0, at_pos))
    query = trim_str(substr_from(value_without_cond, at_pos + 1))
  } else {
    file = value_without_cond
  }
  (file, query, when_cond)
}

///|
/// Parses a multi-line resolve step (indented key-value pairs).
fn parse_multi_line_resolve_step(
  lines : Array[String],
  start : Int,
) -> (@types.ResolveStep?, Int) {
  let kv : Map[String, String] = {}
  let mut i = start
  while i < lines.length() {
    let s = lines[i]
    // Must be double-indented
    if not(is_double_indented(s)) {
      break
    }
    let t = trim_str(s)
    // Skip comments
    if starts_with(t, "#") {
      i += 1
      continue
    }
    match parse_kv_line(t) {
      Some((key, val)) => kv.set(key, val)
      None => ()
    }
    i += 1
  }
  let step = build_resolve_step_from_kv(kv)
  (step, i)
}

///|
/// Builds a ResolveStep from parsed key-value pairs.
fn build_resolve_step_from_kv(kv : Map[String, String]) -> @types.ResolveStep? {
  let type_str = match kv.get("type") {
    Some(t) => t
    None => return None
  }
  let step_type = match @types.ResolveStepType::from_string(type_str) {
    Some(t) => t
    None => return None
  }
  let file = match kv.get("file") {
    Some(f) => f
    None => ""
  }
  let query = match kv.get("query") {
    Some(q) => q
    None => ""
  }
  let files = match kv.get("files") {
    Some(f) => parse_list(f)
    None => []
  }
  let prefix = match kv.get("prefix") {
    Some(p) => p
    None => ""
  }
  let when_cond = match kv.get("when") {
    Some(w) => w
    None => ""
  }
  Some(
    @types.ResolveStep::new(
      step_type,
      file~,
      query~,
      files~,
      prefix~,
      when_condition=when_cond,
    ),
  )
}

///|
fn build_resolver_spec_with_sources(
  kv : Map[String, String],
  aliases : Array[@types.ResolverAlias],
  resolve_chain : Array[@types.ResolveStep],
  header_sources : Array[String],
) -> @types.ResolverSpec {
  // Header sources take precedence over resolver section sources
  let sources = if header_sources.length() > 0 {
    header_sources
  } else {
    get_list(kv, "sources")
  }
  let relative_prefixes = get_list(kv, "relative_prefixes")
  let exts = get_list(kv, "exts")
  let indexes = get_list(kv, "indexes")
  let bare_prefix = get_string(kv, "bare_prefix")
  let module_path_style = get_module_path_style(kv.get("module_path_style"))
  let ns_prefix = get_optional_string(kv, "ns_prefix")
  let ns_segments = get_int(kv, "ns_segments", default=2)
  // Project config and commands
  let project_config = get_string(kv, "project_config")
  let install_cmd = get_string(kv, "install_cmd")
  let build_cmd = get_string(kv, "build_cmd")
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
    resolve_chain~,
    project_config~,
    install_cmd~,
    build_cmd~,
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
