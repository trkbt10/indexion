///|
/// File-to-tree conversion for structural comparison.
/// Extracts function-level AST trees from source files via KGF.

///|
/// Extract tree representations from a source file.
/// Uses KGF to detect language, tokenize, and extract function trees.
/// Falls back to simple whitespace tokenization when KGF is unavailable.
pub fn extract(
  display_name : String,
  content : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Array[@apted.TreeNode] {
  let trees : Array[@apted.TreeNode] = []
  guard registry is Some(reg) else {
    trees.push(content_to_simple_tree(content))
    return trees
  }
  guard reg.detect_from_path(display_name) is Some(lang) else {
    trees.push(content_to_simple_tree(content))
    return trees
  }
  guard reg.get_spec(lang) is Some(spec) else {
    trees.push(content_to_simple_tree(content))
    return trees
  }
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let kgf_tokens = lexer.tokenize(content)
  let funcs = @kgf_features.extract_function_trees(
    kgf_tokens,
    display_name,
    spec~,
  )
  if funcs.is_empty() {
    trees.push(content_to_simple_tree(content))
  } else {
    for func in funcs {
      trees.push(func.1)
    }
  }
  trees
}

///|
/// Build a simple tree from raw content (fallback when KGF unavailable).
fn content_to_simple_tree(content : String) -> @apted.TreeNode {
  let tokens = simple_tokenize(content)
  if tokens.is_empty() {
    return @apted.TreeNode::leaf("empty")
  }
  let children : Array[@apted.TreeNode] = []
  for i, token in tokens {
    if i < 100 {
      children.push(@apted.TreeNode::leaf(truncate_label(token, 20)))
    }
  }
  @apted.TreeNode::node("root", children)
}

///|
fn simple_tokenize(content : String) -> Array[String] {
  let tokens : Array[String] = []
  let current : Array[Char] = []
  for c in content {
    if c == ' ' || c == '\n' || c == '\t' || c == '\r' {
      if current.length() > 0 {
        tokens.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(c)
    }
  }
  if current.length() > 0 {
    tokens.push(String::from_array(current))
  }
  tokens
}

///|
fn truncate_label(s : String, max : Int) -> String {
  let chars = s.to_array()
  if chars.length() <= max {
    return s
  }
  let result : Array[Char] = []
  for i = 0; i < max - 3; i = i + 1 {
    result.push(chars[i])
  }
  result.push('.')
  result.push('.')
  result.push('.')
  String::from_array(result)
}
