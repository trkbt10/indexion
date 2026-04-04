///|
/// Function extraction and TreeNode conversion for similarity analysis.

///|
/// Extracted function with its token range.
pub struct ExtractedFunction {
  /// Function name (identifier).
  name : String
  /// Start token index (inclusive).
  start : Int
  /// End token index (exclusive).
  end : Int
  /// Source file path.
  file : String
}

///|
/// Create a new ExtractedFunction.
pub fn ExtractedFunction::new(
  name : String,
  start : Int,
  end : Int,
  file : String,
) -> ExtractedFunction {
  { name, start, end, file }
}

///|
/// Get the function name.
pub fn ExtractedFunction::get_name(self : ExtractedFunction) -> String {
  self.name
}

///|
/// Get the start token index.
pub fn ExtractedFunction::get_start(self : ExtractedFunction) -> Int {
  self.start
}

///|
/// Get the end token index.
pub fn ExtractedFunction::get_end(self : ExtractedFunction) -> Int {
  self.end
}

///|
/// Get the file path.
pub fn ExtractedFunction::get_file(self : ExtractedFunction) -> String {
  self.file
}

///|
/// Get the token count.
pub fn ExtractedFunction::token_count(self : ExtractedFunction) -> Int {
  self.end - self.start
}

///|
/// Get a qualified name (file::name).
pub fn ExtractedFunction::qualified_name(self : ExtractedFunction) -> String {
  self.file + "::" + self.name
}

///|
/// Extract functions from tokenized source code.
/// Uses the KGF spec's `function_keyword` feature to identify the function declaration
/// keyword, and `keyword_kinds` (from KEYWORD declarations) to skip qualifier keywords.
pub fn extract_functions(
  tokens : Array[@kgf_types.Tok],
  file : String,
  spec~ : @kgf_types.KGFSpec,
) -> Array[ExtractedFunction] {
  let fn_keyword = match spec.get_feature("function_keyword") {
    Some(keywords) => if keywords.length() > 0 { keywords[0] } else { return [] }
    None => return []
  }
  let id_set = build_identifier_set(spec=spec)
  let keyword_kinds = spec.get_keyword_kinds()
  let functions : Array[ExtractedFunction] = []
  let mut i = 0
  while i < tokens.length() {
    let tok = tokens[i]
    if tok.get_kind() == fn_keyword {
      // Find function name (next identifier after optional qualifiers)
      let fn_start = i
      let mut name = ""
      let mut j = i + 1
      // Skip optional qualifiers (TypeIdent::, keywords, etc.) until identifier.
      // An identifier followed by DCOLON is a qualifier (e.g. Type::method),
      // not the function name. The function name is the first identifier NOT
      // followed by DCOLON.
      while j < tokens.length() {
        let t = tokens[j]
        let kind = t.get_kind()
        if is_identifier_kind(kind, id_set~) {
          // Look ahead past whitespace for DCOLON
          let mut peek = j + 1
          while peek < tokens.length() {
            let pk = tokens[peek].get_kind()
            if pk == "NL" || pk == "SKIP" || pk == "WS" {
              peek += 1
            } else {
              break
            }
          }
          if peek < tokens.length() && tokens[peek].get_kind() == "DCOLON" {
            // This identifier is a qualifier (e.g. Type in Type::method) — skip it and the DCOLON
            j = peek + 1
          } else {
            // This is the function name
            name = t.get_text()
            j += 1
            break
          }
        } else if kind == "DCOLON" || keyword_kinds.contains(kind) {
          j += 1
        } else {
          break
        }
      }
      // Find body start (LBRACE)
      let mut body_start = -1
      while j < tokens.length() {
        let t = tokens[j]
        if t.get_kind() == "LBRACE" {
          body_start = j
          break
        } else if t.get_kind() == "NL" && body_start < 0 {
          // Function declaration without body (trait method / signature)
          break
        }
        j += 1
      }
      if body_start >= 0 && name.length() > 0 {
        let fn_end = find_matching_brace(tokens, body_start)
        if fn_end > body_start {
          functions.push(
            ExtractedFunction::new(name, fn_start, fn_end + 1, file),
          )
          i = fn_end + 1
          continue
        }
      }
    }
    i += 1
  }
  functions
}

///|
/// Find matching closing brace for an opening brace.
fn find_matching_brace(tokens : Array[@kgf_types.Tok], open_pos : Int) -> Int {
  let mut depth = 0
  for j = open_pos; j < tokens.length(); j = j + 1 {
    let kind = tokens[j].get_kind()
    if kind == "LBRACE" {
      depth += 1
    } else if kind == "RBRACE" {
      depth -= 1
      if depth == 0 {
        return j
      }
    }
  }
  -1
}

///|
/// Convert token slice to TreeNode for APTED comparison.
/// Uses brace structure to build tree hierarchy.
pub fn tokens_to_tree_node(
  tokens : Array[@kgf_types.Tok],
  start : Int,
  end : Int,
  spec~ : @kgf_types.KGFSpec,
) -> @apted.TreeNode {
  if start >= end {
    return @apted.TreeNode::leaf("Empty")
  }
  let id_set = build_identifier_set(spec=spec)
  build_tree_recursive(tokens, start, end, id_set)
}

///|
/// Recursively build TreeNode from token range.
fn build_tree_recursive(
  tokens : Array[@kgf_types.Tok],
  start : Int,
  end : Int,
  id_set : Map[String, Bool],
) -> @apted.TreeNode {
  let children : Array[@apted.TreeNode] = []
  let mut i = start
  while i < end {
    let tok = tokens[i]
    let kind = tok.get_kind()
    if kind == "LBRACE" || kind == "LPAREN" || kind == "LBRACKET" {
      // Find matching close
      let close = find_matching_bracket(tokens, i, kind)
      if close > i && close < end {
        // Build subtree for nested content
        let subtree = build_tree_recursive(tokens, i + 1, close, id_set)
        let wrapper = @apted.TreeNode::node(bracket_label(kind), [subtree])
        children.push(wrapper)
        i = close + 1
        continue
      }
    } else if kind == "RBRACE" || kind == "RPAREN" || kind == "RBRACKET" {
      // Skip closing brackets (handled by parent)
      i += 1
      continue
    } else if kind == "NL" || kind == "LineComment" || kind == "BlockComment" {
      // Skip whitespace and comments
      i += 1
      continue
    } else {
      // Leaf node for other tokens
      children.push(@apted.TreeNode::leaf(token_label(tok, id_set)))
    }
    i += 1
  }
  // Return single child if only one, otherwise wrap in Seq
  match children.length() {
    0 => @apted.TreeNode::leaf("Empty")
    1 => children[0]
    _ => @apted.TreeNode::node("Seq", children)
  }
}

///|
/// Find matching closing bracket.
fn find_matching_bracket(
  tokens : Array[@kgf_types.Tok],
  open_pos : Int,
  open_kind : String,
) -> Int {
  let close_kind = match open_kind {
    "LBRACE" => "RBRACE"
    "LPAREN" => "RPAREN"
    "LBRACKET" => "RBRACKET"
    _ => return -1
  }
  let mut depth = 0
  for j = open_pos; j < tokens.length(); j = j + 1 {
    let kind = tokens[j].get_kind()
    if kind == open_kind {
      depth += 1
    } else if kind == close_kind {
      depth -= 1
      if depth == 0 {
        return j
      }
    }
  }
  -1
}

///|
/// Get tree label for bracket type.
fn bracket_label(kind : String) -> String {
  match kind {
    "LBRACE" => "Block"
    "LPAREN" => "Paren"
    "LBRACKET" => "Bracket"
    _ => "Group"
  }
}

///|
/// Get tree label for token.
fn token_label(tok : @kgf_types.Tok, id_set : Map[String, Bool]) -> String {
  let kind = tok.get_kind()
  // Include text for identifiers
  if is_identifier_kind(kind, id_set~) {
    kind + ":" + tok.get_text()
  } else {
    kind
  }
}

///|
/// Extract functions and convert to TreeNodes.
pub fn extract_function_trees(
  tokens : Array[@kgf_types.Tok],
  file : String,
  spec~ : @kgf_types.KGFSpec,
) -> Array[(ExtractedFunction, @apted.TreeNode)] {
  let functions = extract_functions(tokens, file, spec=spec)
  let result : Array[(ExtractedFunction, @apted.TreeNode)] = []
  for func in functions {
    let tree = tokens_to_tree_node(tokens, func.start, func.end, spec=spec)
    result.push((func, tree))
  }
  result
}
