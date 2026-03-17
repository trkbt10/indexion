///|
/// Proxy function detection via KGF token analysis.
/// Detects functions whose body is a single forwarding call with no added logic.

///|
/// A detected proxy function that delegates to another function.
pub struct ProxyFunction {
  /// Function name (e.g. "round_ties_even_f32").
  name : String
  /// Source file path.
  file : String
  /// Line number (1-indexed) of the fn keyword.
  line : Int
  /// Parameter names from the function signature.
  params : Array[String]
  /// Qualified delegate target (e.g. "@math.round_ties_even_f32").
  delegate_target : String
  /// Arguments passed to the delegate call.
  delegate_args : Array[String]
  /// True if all function parameters are forwarded to the delegate.
  all_forwarded : Bool
  /// Definition start line (1-indexed, includes preceding ///| doc comment).
  def_start_line : Int
  /// Definition end line (1-indexed, inclusive).
  def_end_line : Int
}

///|
/// A text edit for unwrapping a call site.
pub struct UnwrapEdit {
  /// File path.
  file : String
  /// Start character offset in the file.
  start_offset : Int
  /// End character offset in the file (exclusive).
  end_offset : Int
  /// Original text at the replacement range.
  old_text : String
  /// Replacement text (the delegate target).
  new_text : String
  /// Line number (1-indexed) for display.
  line : Int
}

///|
pub fn UnwrapEdit::new(
  file : String,
  start_offset : Int,
  end_offset : Int,
  old_text : String,
  new_text : String,
  line : Int,
) -> UnwrapEdit {
  { file, start_offset, end_offset, old_text, new_text, line }
}

///|
/// Token kinds that indicate control flow or bindings (non-proxy bodies).
fn is_disqualifying_keyword(kind : String) -> Bool {
  kind == "KW_if" ||
  kind == "KW_match" ||
  kind == "KW_let" ||
  kind == "KW_mut" ||
  kind == "KW_for" ||
  kind == "KW_while" ||
  kind == "KW_return" ||
  kind == "KW_break" ||
  kind == "KW_continue"
}

///|
/// Token kinds to skip when analyzing function body.
fn is_skip_token(kind : String) -> Bool {
  kind == "NL" ||
  kind == "LineComment" ||
  kind == "BlockComment" ||
  kind == "DocComment" ||
  kind == "DocLine" ||
  kind == "DocSection" ||
  kind == "SKIP"
}

///|
/// Detect proxy functions from tokenized source code.
/// A proxy function has a body that consists solely of a single function call
/// forwarding its parameters without additional logic.
///
/// By default, excludes self-delegation (self.field.method) and bare enum
/// constructors (no qualifier) as these are intentional API design patterns.
/// Set `include_self_delegation` or `include_bare_constructors` to include them.
pub fn detect_proxy_functions(
  tokens : Array[@kgf_types.Tok],
  file : String,
  include_self_delegation? : Bool = false,
  include_bare_constructors? : Bool = false,
) -> Array[ProxyFunction] {
  let functions = extract_functions(tokens, file)
  let result : Array[ProxyFunction] = []
  // Build token index → line number mapping
  let token_lines : Array[Int] = Array::make(tokens.length(), 1)
  let mut line = 1
  for i, tok in tokens {
    token_lines[i] = line
    if tok.get_kind() == "NL" {
      line += 1
    }
  }
  for func in functions {
    match analyze_proxy(tokens, func, token_lines) {
      Some(proxy) => {
        // Filter self-delegation (e.g. self.field.method)
        if not(include_self_delegation) &&
          proxy.delegate_target.has_prefix("self.") {
          continue
        }
        // Filter bare constructors (no qualifier — just a name like "Emit", "Str")
        if not(include_bare_constructors) &&
          is_bare_target(proxy.delegate_target) {
          continue
        }
        result.push(proxy)
      }
      None => ()
    }
  }
  result
}

///|
/// Check if a delegate target has no qualifier (no "." or "::").
/// Such targets are typically enum constructors or local function aliases.
fn is_bare_target(target : String) -> Bool {
  let chars = target.to_array()
  for i in 0..<chars.length() {
    if chars[i] == '.' {
      return false
    }
    if i + 1 < chars.length() && chars[i] == ':' && chars[i + 1] == ':' {
      return false
    }
  }
  true
}

///|
/// Analyze a single function to determine if it is a proxy.
fn analyze_proxy(
  tokens : Array[@kgf_types.Tok],
  func : ExtractedFunction,
  token_lines : Array[Int],
) -> ProxyFunction? {
  let start = func.get_start()
  let end = func.get_end()
  if start >= end {
    return None
  }
  // Find the function's body LBRACE
  let mut body_start = -1
  for i = start; i < end; i = i + 1 {
    if tokens[i].get_kind() == "LBRACE" {
      body_start = i
      break
    }
  }
  if body_start < 0 {
    return None
  }
  // Extract parameter names from signature (between first LPAREN and its matching RPAREN, before body LBRACE)
  let params = extract_param_names(tokens, start, body_start)
  // Body tokens: between LBRACE+1 and RBRACE (end-1 is RBRACE)
  let body_end = end - 1 // RBRACE position
  if body_start + 1 >= body_end {
    return None // empty body
  }
  // Filter meaningful body tokens
  let body_tokens : Array[@kgf_types.Tok] = []
  for i = body_start + 1; i < body_end; i = i + 1 {
    let kind = tokens[i].get_kind()
    if is_skip_token(kind) {
      continue
    }
    // Early exit on disqualifying keywords
    if is_disqualifying_keyword(kind) {
      return None
    }
    body_tokens.push(tokens[i])
  }
  if body_tokens.length() == 0 {
    return None
  }
  // Parse as single call expression: [qualifier] callee LPAREN [args] RPAREN
  match parse_single_call(body_tokens) {
    Some((target, args)) => {
      let all_forwarded = check_all_forwarded(params, args)
      let line_num = if start < token_lines.length() {
        token_lines[start]
      } else {
        1
      }
      let end_line = if end - 1 < token_lines.length() {
        token_lines[end - 1]
      } else {
        line_num
      }
      // Find def_start_line: scan backwards for preceding ///| doc comment
      let mut def_start = line_num
      if start > 0 {
        let mut i = start - 1
        while i >= 0 {
          let kind = tokens[i].get_kind()
          if kind == "NL" || kind == "SKIP" {
            i -= 1
            continue
          }
          if kind == "DocComment" || kind == "DocLine" || kind == "DocSection" {
            if i < token_lines.length() {
              def_start = token_lines[i]
            }
            i -= 1
            continue
          }
          break
        }
      }
      Some({
        name: func.get_name(),
        file: func.get_file(),
        line: line_num,
        params,
        delegate_target: target,
        delegate_args: args,
        all_forwarded,
        def_start_line: def_start,
        def_end_line: end_line,
      })
    }
    None => None
  }
}

///|
/// Extract parameter names from function signature tokens.
/// Scans from start to body_start, finds the first LPAREN/RPAREN pair,
/// and collects Ident tokens that are in parameter name position.
fn extract_param_names(
  tokens : Array[@kgf_types.Tok],
  start : Int,
  body_start : Int,
) -> Array[String] {
  let params : Array[String] = []
  // Find signature LPAREN (skip fn keyword, optional type qualifiers, function name)
  let mut paren_start = -1
  for i = start; i < body_start; i = i + 1 {
    if tokens[i].get_kind() == "LPAREN" {
      paren_start = i
      break
    }
  }
  if paren_start < 0 {
    return params
  }
  // Find matching RPAREN
  let mut depth = 0
  let mut paren_end = -1
  for i = paren_start; i < body_start; i = i + 1 {
    let kind = tokens[i].get_kind()
    if kind == "LPAREN" {
      depth += 1
    } else if kind == "RPAREN" {
      depth -= 1
      if depth == 0 {
        paren_end = i
        break
      }
    }
  }
  if paren_end < 0 {
    return params
  }
  // Collect parameter names: Ident tokens that appear before COLON or TILDE
  // Pattern per param: Ident [TILDE] [COLON Type...] [COMMA]
  // We want the Ident at the start of each parameter (after COMMA or LPAREN)
  let mut expecting_param = true
  for i = paren_start + 1; i < paren_end; i = i + 1 {
    let kind = tokens[i].get_kind()
    if is_skip_token(kind) {
      continue
    }
    if expecting_param && (is_identifier_kind(kind) || kind == "Ident") {
      params.push(tokens[i].get_text())
      expecting_param = false
    } else if kind == "COMMA" {
      expecting_param = true
    }
  }
  // Filter out "self" — it's part of method receiver, not a forwarded param
  let filtered : Array[String] = []
  for p in params {
    if p != "self" {
      filtered.push(p)
    }
  }
  filtered
}

///|
/// Try to parse body tokens as a single call expression.
/// Returns (delegate_target, args) if successful.
/// Pattern: [qualifier] callee LPAREN [args] RPAREN
fn parse_single_call(
  body_tokens : Array[@kgf_types.Tok],
) -> (String, Array[String])? {
  let len = body_tokens.length()
  if len < 2 {
    return None // Minimum: callee LPAREN RPAREN = 3 tokens, but 0-arg = callee()
  }
  // Last token must be RPAREN
  if body_tokens[len - 1].get_kind() != "RPAREN" {
    return None
  }
  // Find the matching LPAREN for the final RPAREN
  let mut depth = 0
  let mut call_lparen = -1
  for i = len - 1; i >= 0; i = i - 1 {
    let kind = body_tokens[i].get_kind()
    if kind == "RPAREN" {
      depth += 1
    } else if kind == "LPAREN" {
      depth -= 1
      if depth == 0 {
        call_lparen = i
        break
      }
    }
  }
  if call_lparen < 1 {
    // Need at least one token before LPAREN (the callee)
    return None
  }
  // Everything before call_lparen is the qualifier + callee
  // Parse qualifier chain
  let target = build_call_target(body_tokens, 0, call_lparen)
  if target.length() == 0 {
    return None
  }
  // Parse arguments between LPAREN and RPAREN
  match parse_call_args(body_tokens, call_lparen + 1, len - 1) {
    Some(args) => Some((target, args))
    None => None
  }
}

///|
/// Build the delegate target string from qualifier + callee tokens.
/// Valid patterns: PackageRef DOT [PackageRef DOT | TypeIdent DCOLON]* Ident
///                 TypeIdent DCOLON Ident
///                 Ident DOT Ident [DOT Ident]*
fn build_call_target(
  tokens : Array[@kgf_types.Tok],
  start : Int,
  end : Int,
) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    let kind = tokens[i].get_kind()
    let text = tokens[i].get_text()
    if kind == "PackageRef" ||
      is_identifier_kind(kind) ||
      kind == "TypeIdent" ||
      kind == "Ident" {
      buf.write_string(text)
    } else if kind == "DOT" {
      buf.write_string(".")
    } else if kind == "DCOLON" {
      buf.write_string("::")
    } else {
      // Unexpected token in qualifier — not a valid call target
      return ""
    }
  }
  buf.to_string()
}

///|
/// Parse call arguments. Only allows simple identifier references (with optional TILDE for labeled args).
/// Returns None if any argument is an expression (not a simple forwarding).
fn parse_call_args(
  tokens : Array[@kgf_types.Tok],
  start : Int,
  end : Int,
) -> Array[String]? {
  let args : Array[String] = []
  if start >= end {
    return Some(args) // zero arguments
  }
  let mut i = start
  while i < end {
    let kind = tokens[i].get_kind()
    if is_skip_token(kind) {
      i += 1
      continue
    }
    // Expect an identifier (possibly with TILDE for labeled args)
    if is_identifier_kind(kind) || kind == "Ident" {
      args.push(tokens[i].get_text())
      i += 1
      // Skip optional TILDE after ident (labeled arg shorthand: name~)
      if i < end && tokens[i].get_kind() == "TILDE" {
        i += 1
      }
      // Skip optional = Ident (named arg: name=value)
      if i < end && tokens[i].get_kind() == "EQ" {
        i += 1
        if i < end &&
          (
            is_identifier_kind(tokens[i].get_kind()) ||
            tokens[i].get_kind() == "Ident"
          ) {
          // Replace the arg name with the value being passed
          args[args.length() - 1] = tokens[i].get_text()
          i += 1
        } else {
          return None // Expression after =, not a simple forwarding
        }
      }
      // Expect COMMA or end
      if i < end {
        if tokens[i].get_kind() == "COMMA" {
          i += 1
        } else if is_skip_token(tokens[i].get_kind()) {
          i += 1
        } else {
          return None // Unexpected token after argument
        }
      }
    } else {
      return None // Not a simple identifier — it's an expression
    }
  }
  Some(args)
}

///|
/// Check if all function parameters are forwarded in the call arguments.
fn check_all_forwarded(params : Array[String], args : Array[String]) -> Bool {
  if params.length() != args.length() {
    return false
  }
  for i in 0..<params.length() {
    if params[i] != args[i] {
      return false
    }
  }
  true
}

///|
/// Convenience: detect proxy functions from file content using KGF registry.
pub fn detect_proxy_functions_from_file(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
  include_self_delegation? : Bool = false,
  include_bare_constructors? : Bool = false,
) -> Array[ProxyFunction] {
  let reg = match registry {
    Some(r) => r
    None => return []
  }
  let lang = match reg.detect_from_path(path) {
    Some(l) => l
    None => return []
  }
  let spec = match reg.get_spec(lang) {
    Some(s) => s
    None => return []
  }
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(content)
  detect_proxy_functions(
    tokens,
    path,
    include_self_delegation~,
    include_bare_constructors~,
  )
}

///|
/// Find call sites of a wrapper function in tokenized source code.
/// Returns edits that replace the call target with the delegate target.
pub fn find_call_sites(
  wrapper_name : String,
  delegate_target : String,
  tokens : Array[@kgf_types.Tok],
  file : String,
) -> Array[UnwrapEdit] {
  let edits : Array[UnwrapEdit] = []
  // Build token index → line number mapping
  let token_lines : Array[Int] = Array::make(tokens.length(), 1)
  let mut line = 1
  for i, tok in tokens {
    token_lines[i] = line
    if tok.get_kind() == "NL" {
      line += 1
    }
  }
  let mut i = 0
  while i < tokens.length() {
    let tok = tokens[i]
    let kind = tok.get_kind()
    let text = tok.get_text()
    // Pattern 1: Ident("wrapper_name") LPAREN (not preceded by KW_fn)
    if (kind == "Ident" || is_identifier_kind(kind)) && text == wrapper_name {
      // Check next meaningful token is LPAREN
      let mut next = i + 1
      while next < tokens.length() && is_skip_token(tokens[next].get_kind()) {
        next += 1
      }
      if next < tokens.length() && tokens[next].get_kind() == "LPAREN" {
        // Check not preceded by KW_fn (definition, not call)
        let mut prev = i - 1
        while prev >= 0 && is_skip_token(tokens[prev].get_kind()) {
          prev -= 1
        }
        let is_def = prev >= 0 &&
          (
            tokens[prev].get_kind() == "KW_fn" ||
            tokens[prev].get_kind() == "DCOLON" ||
            tokens[prev].get_kind() == "DOT"
          )
        if not(is_def) {
          let start_offset = tok.get_pos()
          let end_offset = tok.get_pos() + text.length()
          edits.push({
            file,
            start_offset,
            end_offset,
            old_text: text,
            new_text: delegate_target,
            line: if i < token_lines.length() {
              token_lines[i]
            } else {
              1
            },
          })
        }
      }
    }
    // Pattern 2: PackageRef DOT Ident("wrapper_name") LPAREN
    if kind == "PackageRef" {
      // Look ahead: DOT Ident("wrapper_name") LPAREN
      let mut j = i + 1
      while j < tokens.length() && is_skip_token(tokens[j].get_kind()) {
        j += 1
      }
      if j < tokens.length() && tokens[j].get_kind() == "DOT" {
        let mut k = j + 1
        while k < tokens.length() && is_skip_token(tokens[k].get_kind()) {
          k += 1
        }
        if k < tokens.length() &&
          (
            tokens[k].get_kind() == "Ident" ||
            is_identifier_kind(tokens[k].get_kind())
          ) &&
          tokens[k].get_text() == wrapper_name {
          // Check LPAREN follows
          let mut next = k + 1
          while next < tokens.length() && is_skip_token(tokens[next].get_kind()) {
            next += 1
          }
          if next < tokens.length() && tokens[next].get_kind() == "LPAREN" {
            // Check not preceded by KW_fn
            let mut prev = i - 1
            while prev >= 0 && is_skip_token(tokens[prev].get_kind()) {
              prev -= 1
            }
            let is_def = prev >= 0 && tokens[prev].get_kind() == "KW_fn"
            if not(is_def) {
              let start_offset = tok.get_pos()
              let end_offset = tokens[k].get_pos() +
                tokens[k].get_text().length()
              let old = text + "." + tokens[k].get_text()
              // Skip if already calling the delegate target directly
              if old == delegate_target {
                i += 1
                continue
              }
              edits.push({
                file,
                start_offset,
                end_offset,
                old_text: old,
                new_text: delegate_target,
                line: if i < token_lines.length() {
                  token_lines[i]
                } else {
                  1
                },
              })
            }
          }
        }
      }
    }
    i += 1
  }
  edits
}

///|
/// Apply character-offset edits to content string.
/// Sorts edits by offset descending (back-to-front) so earlier offsets stay valid.
pub fn apply_edits(content : String, edits : Array[UnwrapEdit]) -> String {
  let sorted = edits.copy()
  sorted.sort_by(fn(a, b) { b.start_offset - a.start_offset })
  let mut buf = content
  for edit in sorted {
    let buf_chars = buf.to_array()
    let before_arr : Array[Char] = []
    for j = 0; j < edit.start_offset && j < buf_chars.length(); j = j + 1 {
      before_arr.push(buf_chars[j])
    }
    let after_arr : Array[Char] = []
    for j = edit.end_offset; j < buf_chars.length(); j = j + 1 {
      after_arr.push(buf_chars[j])
    }
    buf = String::from_array(before_arr) +
      edit.new_text +
      String::from_array(after_arr)
  }
  buf
}

///|
/// Delete lines from content (1-indexed, inclusive range).
/// Also removes a blank line left after deletion if present.
pub fn delete_lines(
  content : String,
  start_line : Int,
  end_line : Int,
) -> String {
  let lines = split_by_newline(content)
  let result : Array[String] = []
  for i, line in lines {
    let line_num = i + 1
    if line_num >= start_line && line_num <= end_line {
      continue
    }
    result.push(line)
  }
  // Remove extra blank line at deletion point
  let del_idx = start_line - 1
  if del_idx > 0 && del_idx < result.length() {
    if is_blank(result[del_idx - 1]) && is_blank(result[del_idx]) {
      let cleaned : Array[String] = []
      for i, line in result {
        if i == del_idx {
          continue
        }
        cleaned.push(line)
      }
      return join_lines(cleaned)
    }
  }
  join_lines(result)
}

///|
fn is_blank(s : String) -> Bool {
  let chars = s.to_array()
  for c in chars {
    if c != ' ' && c != '\t' && c != '\r' {
      return false
    }
  }
  true
}

///|
fn split_by_newline(text : String) -> Array[String] {
  let lines : Array[String] = []
  let chars = text.to_array()
  let buf : Array[Char] = []
  for c in chars {
    if c == '\n' {
      lines.push(String::from_array(buf))
      buf.clear()
    } else if c == '\r' {
      continue
    } else {
      buf.push(c)
    }
  }
  if buf.length() > 0 {
    lines.push(String::from_array(buf))
  }
  lines
}

///|
fn join_lines(lines : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i, line in lines {
    if i > 0 {
      buf.write_string("\n")
    }
    buf.write_string(line)
  }
  // Preserve trailing newline
  if lines.length() > 0 {
    buf.write_string("\n")
  }
  buf.to_string()
}
