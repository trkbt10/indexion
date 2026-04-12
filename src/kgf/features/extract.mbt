///|
/// Function extraction and TreeNode conversion for similarity analysis.
/// Uses KGF grammar pipeline (tokenize→parse→eval_semantics→declares edges)
/// for accurate function boundary detection across all languages.

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
pub fn ExtractedFunction::new(
  name : String,
  start : Int,
  end : Int,
  file : String,
) -> ExtractedFunction {
  { name, start, end, file }
}

///|
pub fn ExtractedFunction::get_name(self : ExtractedFunction) -> String {
  self.name
}

///|
pub fn ExtractedFunction::get_start(self : ExtractedFunction) -> Int {
  self.start
}

///|
pub fn ExtractedFunction::get_end(self : ExtractedFunction) -> Int {
  self.end
}

///|
pub fn ExtractedFunction::get_file(self : ExtractedFunction) -> String {
  self.file
}

///|
pub fn ExtractedFunction::token_count(self : ExtractedFunction) -> Int {
  self.end - self.start
}

///|
pub fn ExtractedFunction::qualified_name(self : ExtractedFunction) -> String {
  self.file + "::" + self.name
}

///|
/// Extract functions from source code using KGF grammar pipeline.
/// All function boundary detection is done by the grammar (tokenize→parse→
/// eval_semantics→declares edges). No language-specific heuristics.
///
/// Returns ExtractedFunction with token indices from PubDeclaration.start_tok/end_tok.
pub fn extract_functions(
  content : String,
  file : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Array[ExtractedFunction] {
  let (decls, _) = @kgf_declarations.extract_declarations(
    content, file, registry, visibility=All,
  )
  let functions : Array[ExtractedFunction] = []
  for decl in decls {
    if decl.category != "function" {
      continue
    }
    if decl.start_tok >= 0 && decl.end_tok > decl.start_tok {
      functions.push(
        ExtractedFunction::new(decl.name, decl.start_tok, decl.end_tok, file),
      )
    }
  }
  functions
}

///|
/// Extract functions and convert to TreeNodes for structural comparison.
/// Requires tokens array for tree construction.
pub fn extract_function_trees(
  content : String,
  file : String,
  tokens : Array[@kgf_types.Tok],
  registry : @kgf_registry.KGFRegistry?,
  spec~ : @kgf_types.KGFSpec,
) -> Array[(ExtractedFunction, @apted.TreeNode)] {
  let functions = extract_functions(content, file, registry)
  let result : Array[(ExtractedFunction, @apted.TreeNode)] = []
  for func in functions {
    let tree = tokens_to_tree_node(tokens, func.start, func.end, spec~)
    result.push((func, tree))
  }
  result
}

///|
/// Convert token slice to TreeNode for APTED comparison.
/// Uses bracket structure to build tree hierarchy.
pub fn tokens_to_tree_node(
  tokens : Array[@kgf_types.Tok],
  start : Int,
  end : Int,
  spec~ : @kgf_types.KGFSpec,
) -> @apted.TreeNode {
  if start >= end {
    return @apted.TreeNode::leaf("Empty")
  }
  let id_set = build_identifier_set(spec~)
  build_tree_recursive(tokens, start, end, id_set)
}

///|
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
      let close = find_matching_bracket(tokens, i, kind)
      if close > i && close < end {
        let subtree = build_tree_recursive(tokens, i + 1, close, id_set)
        let wrapper = @apted.TreeNode::node(bracket_label(kind), [subtree])
        children.push(wrapper)
        i = close + 1
        continue
      }
    } else if kind == "RBRACE" || kind == "RPAREN" || kind == "RBRACKET" {
      i += 1
      continue
    } else if kind == "NL" || kind == "LineComment" || kind == "BlockComment" {
      i += 1
      continue
    } else {
      children.push(@apted.TreeNode::leaf(token_label(tok, id_set)))
    }
    i += 1
  }
  match children.length() {
    0 => @apted.TreeNode::leaf("Empty")
    1 => children[0]
    _ => @apted.TreeNode::node("Seq", children)
  }
}

///|
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
fn bracket_label(kind : String) -> String {
  match kind {
    "LBRACE" => "Block"
    "LPAREN" => "Paren"
    "LBRACKET" => "Bracket"
    _ => "Group"
  }
}

///|
fn token_label(tok : @kgf_types.Tok, id_set : Map[String, Bool]) -> String {
  let kind = tok.get_kind()
  if is_identifier_kind(kind, id_set~) {
    kind + ":" + tok.get_text()
  } else {
    kind
  }
}
