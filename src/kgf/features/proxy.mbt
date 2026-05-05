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
/// Build set of keywords that are allowed in proxy function bodies.
/// Delegates to LanguageToolkit::get_allowed_keywords for the cached result.
fn _build_allowed_keywords(spec : @kgf_types.KGFSpec) -> Map[String, Bool] {
  @kgf_toolkit.LanguageToolkit::from_spec(spec).get_allowed_keywords()
}

///|
/// Build set of qualifier separator token kinds from KGF spec's
/// `qualifier_separators` feature (e.g. DOT, DCOLON, OBJOP, SCOPE, ARROW).
fn _build_qualifier_separator_set(
  spec : @kgf_types.KGFSpec,
) -> Map[String, Bool] {
  @kgf_toolkit.LanguageToolkit::from_spec(spec).get_qualifier_separators()
}

///|
/// Build set of self-keyword token kinds from KGF spec's `self_keyword` feature.
fn _build_self_keyword_set(spec : @kgf_types.KGFSpec) -> Map[String, Bool] {
  @kgf_toolkit.LanguageToolkit::from_spec(spec).get_self_keywords()
}

///|
/// Token kinds that indicate control flow or bindings (non-proxy bodies).
/// A keyword token in a function body likely means the body contains logic
/// beyond a simple forwarding call.
/// Keywords listed in `function_keyword` and `self_keyword` features are
/// allowed because they represent closures/lambdas or method receivers.
fn is_disqualifying_keyword(
  kind : String,
  spec~ : @kgf_types.KGFSpec,
  allowed_kw : Map[String, Bool],
) -> Bool {
  if !spec.is_keyword(kind) {
    return false
  }
  !allowed_kw.contains(kind)
}

///|
/// Token kinds to skip when analyzing function body.
/// Skips whitespace/newlines (NL, SKIP, WS), comments (*Comment suffix),
/// and doc tokens (Doc* prefix). These are KGF naming conventions shared
/// across all language specs — every comment token name in kgfs/programming/
/// ends in "Comment" (LineComment, BlockComment, DocComment, Comment), so a
/// suffix check is both correct and O(|kind|) instead of O(|kind|²).
fn is_skip_token(kind : String) -> Bool {
  kind == "NL" ||
  kind == "SKIP" ||
  kind == "WS" ||
  kind.has_prefix("Doc") ||
  kind.has_suffix("Comment")
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
  content : String,
  file : String,
  registry : @kgf_registry.KGFRegistry?,
  include_self_delegation? : Bool = false,
  include_bare_constructors? : Bool = false,
  spec~ : @kgf_types.KGFSpec,
) -> Array[ProxyFunction] {
  // Get all declarations from parse events (visibility-independent)
  let (all_decls, _) = @kgf_declarations.extract_declarations(
    content,
    file,
    registry,
    visibility=All,
  )
  // Filter to function declarations
  let functions : Array[ExtractedFunction] = []
  for decl in all_decls {
    if decl.category == "function" &&
      decl.start_tok >= 0 &&
      decl.end_tok > decl.start_tok {
      functions.push(
        ExtractedFunction::new(decl.name, decl.start_tok, decl.end_tok, file),
      )
    }
  }
  // Tokenize with the same preprocessed content that the parser used.
  // Use LanguageToolkit for cached lexer and feature sets.
  let toolkit = @kgf_toolkit.LanguageToolkit::from_spec(spec)
  let prepared = toolkit.preprocess(content)
  let tokens = toolkit.get_lexer().tokenize(prepared)
  let id_set = toolkit.get_identifier_set()
  let allowed_kw = toolkit.get_allowed_keywords()
  let qualifier_set = toolkit.get_qualifier_separators()
  let self_kw_set = toolkit.get_self_keywords()
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
    match
      analyze_proxy(
        tokens,
        func,
        token_lines,
        id_set,
        spec~,
        allowed_kw,
        qualifier_set~,
        self_kw_set~,
      ) {
      Some((proxy, call_info)) => {
        // Filter self-delegation (e.g. self.field.method) using KGF self_keyword
        if !include_self_delegation && call_info.starts_with_self {
          continue
        }
        // Filter bare constructors (no qualifier separator found in call target)
        if !include_bare_constructors && !call_info.has_qualifier {
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
/// Analyze a single function to determine if it is a proxy.
/// Returns the proxy function along with call target metadata for filtering.
fn analyze_proxy(
  tokens : Array[@kgf_types.Tok],
  func : ExtractedFunction,
  token_lines : Array[Int],
  id_set : Map[String, Bool],
  spec~ : @kgf_types.KGFSpec,
  allowed_kw : Map[String, Bool],
  qualifier_set~ : Map[String, Bool],
  self_kw_set~ : Map[String, Bool],
) -> (ProxyFunction, CallTargetResult)? {
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
  let params = extract_param_names(
    tokens,
    start,
    body_start,
    id_set,
    self_kw_set~,
  )
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
    if is_disqualifying_keyword(kind, spec~, allowed_kw) {
      return None
    }
    body_tokens.push(tokens[i])
  }
  if body_tokens.length() == 0 {
    return None
  }
  // Parse as single call expression: [qualifier] callee LPAREN [args] RPAREN
  match parse_single_call(body_tokens, id_set, qualifier_set~, self_kw_set~) {
    Some((call_result, args)) => {
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
      Some(
        (
          {
            name: func.get_name(),
            file: func.get_file(),
            line: line_num,
            params,
            delegate_target: call_result.target,
            delegate_args: args,
            all_forwarded,
            def_start_line: def_start,
            def_end_line: end_line,
          },
          call_result,
        ),
      )
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
  id_set : Map[String, Bool],
  self_kw_set~ : Map[String, Bool],
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
    if expecting_param && is_identifier_kind(kind, id_set~) {
      params.push(tokens[i].get_text())
      expecting_param = false
    } else if expecting_param && self_kw_set.contains(kind) {
      // Skip self keyword — it's a method receiver, not a forwarded param
      expecting_param = false
    } else if kind == "COMMA" {
      expecting_param = true
    }
  }
  params
}

///|
/// Try to parse body tokens as a single call expression.
/// Returns (CallTargetResult, args) if successful.
/// Pattern: [qualifier] callee LPAREN [args] RPAREN
fn parse_single_call(
  body_tokens : Array[@kgf_types.Tok],
  id_set : Map[String, Bool],
  qualifier_set~ : Map[String, Bool],
  self_kw_set~ : Map[String, Bool],
) -> (CallTargetResult, Array[String])? {
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
  let result = build_call_target(
    body_tokens,
    0,
    call_lparen,
    id_set,
    qualifier_set~,
    self_kw_set~,
  )
  if result.target.length() == 0 {
    return None
  }
  // Parse arguments between LPAREN and RPAREN
  match parse_call_args(body_tokens, call_lparen + 1, len - 1, id_set) {
    Some(args) => Some((result, args))
    None => None
  }
}

///|
/// Result of building a call target from tokens.
/// Carries the target string along with metadata about its structure,
/// so callers don't need to re-parse the string with hardcoded patterns.
priv struct CallTargetResult {
  /// The delegate target string (e.g. "@math.round", "Type::method", "self.field").
  target : String
  /// True if the target contains at least one qualifier separator.
  has_qualifier : Bool
  /// True if the first token is a self keyword (e.g. self.field.method).
  starts_with_self : Bool
}

///|
/// Build the delegate target string from qualifier + callee tokens.
/// Uses KGF-defined qualifier separators and self keywords instead of
/// hardcoded DOT/DCOLON/"self." checks.
fn build_call_target(
  tokens : Array[@kgf_types.Tok],
  start : Int,
  end : Int,
  id_set : Map[String, Bool],
  qualifier_set~ : Map[String, Bool],
  self_kw_set~ : Map[String, Bool],
) -> CallTargetResult {
  let buf = StringBuilder::new()
  let mut has_qualifier = false
  let mut starts_with_self = false
  for i = start; i < end; i = i + 1 {
    let kind = tokens[i].get_kind()
    let text = tokens[i].get_text()
    if is_identifier_kind(kind, id_set~) || self_kw_set.contains(kind) {
      buf.write_string(text)
      if i == start && self_kw_set.contains(kind) {
        starts_with_self = true
      }
    } else if qualifier_set.contains(kind) {
      buf.write_string(text)
      has_qualifier = true
    } else {
      // Unexpected token in qualifier — not a valid call target
      return { target: "", has_qualifier: false, starts_with_self: false }
    }
  }
  { target: buf.to_string(), has_qualifier, starts_with_self }
}

///|
/// Parse call arguments. Only allows simple identifier references (with optional TILDE for labeled args).
/// Returns None if any argument is an expression (not a simple forwarding).
fn parse_call_args(
  tokens : Array[@kgf_types.Tok],
  start : Int,
  end : Int,
  id_set : Map[String, Bool],
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
    if is_identifier_kind(kind, id_set~) {
      args.push(tokens[i].get_text())
      i += 1
      // Skip optional TILDE after ident (labeled arg shorthand: name~)
      if i < end && tokens[i].get_kind() == "TILDE" {
        i += 1
      }
      // Skip optional = Ident (named arg: name=value)
      if i < end && tokens[i].get_kind() == "EQ" {
        i += 1
        if i < end && is_identifier_kind(tokens[i].get_kind(), id_set~) {
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
  detect_proxy_functions(
    content,
    path,
    registry,
    include_self_delegation~,
    include_bare_constructors~,
    spec~,
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
  spec~ : @kgf_types.KGFSpec,
) -> Array[UnwrapEdit] {
  let toolkit = @kgf_toolkit.LanguageToolkit::from_spec(spec)
  let id_set = toolkit.get_identifier_set()
  let qualifier_set = toolkit.get_qualifier_separators()
  // Resolve function keyword from spec to distinguish definitions from calls
  let fn_keyword = match spec.get_feature("function_keyword") {
    Some(keywords) =>
      if keywords.length() > 0 {
        keywords[0]
      } else {
        return []
      }
    None => return []
  }
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
    // Pattern 1: Ident("wrapper_name") LPAREN (not preceded by function keyword)
    if is_identifier_kind(kind, id_set~) && text == wrapper_name {
      // Check next meaningful token is LPAREN
      let mut next = i + 1
      while next < tokens.length() && is_skip_token(tokens[next].get_kind()) {
        next += 1
      }
      if next < tokens.length() && tokens[next].get_kind() == "LPAREN" {
        // Check not preceded by function keyword or qualifier separator (definition, not call)
        let mut prev = i - 1
        while prev >= 0 && is_skip_token(tokens[prev].get_kind()) {
          prev -= 1
        }
        let is_def = prev >= 0 &&
          (
            tokens[prev].get_kind() == fn_keyword ||
            qualifier_set.contains(tokens[prev].get_kind())
          )
        if !is_def {
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
    // Pattern 2: PackageRef <qualifier_sep> Ident("wrapper_name") LPAREN
    if kind == "PackageRef" {
      // Look ahead: qualifier_separator Ident("wrapper_name") LPAREN
      let mut j = i + 1
      while j < tokens.length() && is_skip_token(tokens[j].get_kind()) {
        j += 1
      }
      if j < tokens.length() && qualifier_set.contains(tokens[j].get_kind()) {
        let sep_text = tokens[j].get_text()
        let mut k = j + 1
        while k < tokens.length() && is_skip_token(tokens[k].get_kind()) {
          k += 1
        }
        if k < tokens.length() &&
          is_identifier_kind(tokens[k].get_kind(), id_set~) &&
          tokens[k].get_text() == wrapper_name {
          // Check LPAREN follows
          let mut next = k + 1
          while next < tokens.length() && is_skip_token(tokens[next].get_kind()) {
            next += 1
          }
          if next < tokens.length() && tokens[next].get_kind() == "LPAREN" {
            // Check not preceded by function keyword
            let mut prev = i - 1
            while prev >= 0 && is_skip_token(tokens[prev].get_kind()) {
              prev -= 1
            }
            let is_def = prev >= 0 && tokens[prev].get_kind() == fn_keyword
            if !is_def {
              let start_offset = tok.get_pos()
              let end_offset = tokens[k].get_pos() +
                tokens[k].get_text().length()
              let old = text + sep_text + tokens[k].get_text()
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
/// Sorts edits by offset ascending and emits the output in a single pass so
/// N edits cost O(|content| + Σ|new_text|) rather than O(N·|content|).
pub fn apply_edits(content : String, edits : Array[UnwrapEdit]) -> String {
  if edits.length() == 0 {
    return content
  }
  let sorted = edits.copy()
  sorted.sort_by(fn(a, b) { a.start_offset - b.start_offset })
  let chars = content.to_array()
  let len = chars.length()
  let buf = StringBuilder::new(size_hint=len)
  let mut cursor = 0
  for edit in sorted {
    let start = if edit.start_offset < 0 {
      0
    } else if edit.start_offset > len {
      len
    } else {
      edit.start_offset
    }
    // Overlapping or out-of-order edits: skip the later one rather than
    // corrupt the output. Callers can detect this by diffing lengths.
    if start < cursor {
      continue
    }
    for j = cursor; j < start; j = j + 1 {
      buf.write_char(chars[j])
    }
    buf.write_string(edit.new_text)
    let end = if edit.end_offset > len {
      len
    } else if edit.end_offset < start {
      start
    } else {
      edit.end_offset
    }
    cursor = end
  }
  for j = cursor; j < len; j = j + 1 {
    buf.write_char(chars[j])
  }
  buf.to_string()
}

///|
/// Delete lines from content (1-indexed, inclusive range).
/// Also removes a blank line left after deletion if present.
pub fn delete_lines(
  content : String,
  start_line : Int,
  end_line : Int,
) -> String {
  let lines = @text_ops.split_by_newline(content)
  let result : Array[String] = []
  for i, line in lines {
    let line_num = i + 1
    if line_num >= start_line && line_num <= end_line {
      continue
    }
    result.push(line)
  }
  let del_idx = start_line - 1
  if del_idx > 0 &&
    del_idx < result.length() &&
    is_blank(result[del_idx - 1]) &&
    is_blank(result[del_idx]) {
    result.remove(del_idx) |> ignore
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
