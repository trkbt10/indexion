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
/// Extract functions from source code using KGF grammar pipeline.
/// Uses the full KGF pipeline (tokenize→parse→eval_semantics→declares edges)
/// for accurate function boundary detection across all languages.
///
/// The `content` parameter is the source text; `registry` is the KGF registry.
/// The `tokens` parameter is retained for compatibility with callers that
/// already have a token array (e.g. for tree extraction), but the function
/// detection itself is grammar-based.
pub fn extract_functions(
  tokens : Array[@kgf_types.Tok],
  file : String,
  content? : String = "",
  registry? : @kgf_registry.KGFRegistry? = None,
  spec~ : @kgf_types.KGFSpec,
) -> Array[ExtractedFunction] {
  // Reconstruct content from tokens if not provided
  let resolved_content = if content.length() > 0 {
    content
  } else {
    reconstruct_content_from_tokens(tokens)
  }
  let (decls, _) = @kgf_declarations.extract_pub_declarations_and_doc_map(
    resolved_content, file, registry,
  )
  let functions : Array[ExtractedFunction] = []
  for decl in decls {
    if decl.category != "function" {
      continue
    }
    // Use token indices from PubDeclaration if available,
    // otherwise fall back to scanning tokens for the name
    let start_tok = if decl.start_tok >= 0 {
      decl.start_tok
    } else {
      find_token_by_name(tokens, decl.name, spec)
    }
    let end_tok = if decl.end_tok >= 0 {
      decl.end_tok
    } else if start_tok >= 0 {
      // Approximate: scan forward to find closing brace/end
      tokens.length()
    } else {
      continue
    }
    if start_tok >= 0 && end_tok > start_tok {
      functions.push(ExtractedFunction::new(decl.name, start_tok, end_tok, file))
    }
  }
  functions
}

///|
/// Reconstruct source content from token array.
/// Used as fallback when content string is not provided.
fn reconstruct_content_from_tokens(tokens : Array[@kgf_types.Tok]) -> String {
  let buf = StringBuilder::new()
  for tok in tokens {
    buf.write_string(tok.get_text())
  }
  buf.to_string()
}

///|
/// Find the first token matching a function name (identifier followed by LPAREN).
fn find_token_by_name(
  tokens : Array[@kgf_types.Tok],
  name : String,
  spec : @kgf_types.KGFSpec,
) -> Int {
  let id_set = build_identifier_set(spec~)
  for i, tok in tokens {
    if is_identifier_kind(tok.get_kind(), id_set~) && tok.get_text() == name {
      // Check if followed by LPAREN (skipping whitespace)
      let mut j = i + 1
      while j < tokens.length() {
        let kind = tokens[j].get_kind()
        if kind == "NL" || kind == "SKIP" || kind == "WS" {
          j += 1
        } else {
          break
        }
      }
      if j < tokens.length() && tokens[j].get_kind() == "LPAREN" {
        return i
      }
    }
  }
  -1
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
  let id_set = build_identifier_set(spec~)
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
  let functions = extract_functions(tokens, file, spec~)
  let result : Array[(ExtractedFunction, @apted.TreeNode)] = []
  for func in functions {
    let tree = tokens_to_tree_node(tokens, func.start, func.end, spec~)
    result.push((func, tree))
  }
  result
}
