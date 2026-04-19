///|
/// Token types for the PEG expression tokenizer.
/// Supports full PEG operator set (Ford 2004).
priv enum GrammarToken {
  IDENT(String)
  LP
  RP
  LB
  RB
  STAR
  PLUS
  Q
  BAR
  COLON
  AMP // & - And-predicate (positive lookahead)
  EXCL // ! - Not-predicate (negative lookahead)
  SLASH // / - Prioritized choice (PEG standard, alias for |)
}

///|
/// Parser state holding tokens and current position.
priv struct ParseState {
  tokens : Array[GrammarToken]
  mut pos : Int
  warnings : Array[String]
}

///|
/// Creates a new parse state from tokens.
fn ParseState::new(tokens : Array[GrammarToken]) -> ParseState {
  { tokens, pos: 0, warnings: [] }
}

///|
/// Adds a deprecation warning.
fn ParseState::warn_deprecated(self : ParseState, msg : String) -> Unit {
  self.warnings.push(msg)
}

///|
/// Returns true if there are more tokens.
fn ParseState::has_more(self : ParseState) -> Bool {
  self.pos < self.tokens.length()
}

///|
/// Peeks at the current token without consuming it.
fn ParseState::peek(self : ParseState) -> GrammarToken? {
  if self.pos < self.tokens.length() {
    Some(self.tokens[self.pos])
  } else {
    None
  }
}

///|
/// Consumes the current token and advances.
fn ParseState::advance(self : ParseState) -> Unit {
  if self.pos < self.tokens.length() {
    self.pos += 1
  }
}

///|
/// Checks if current token matches and consumes it if so.
fn ParseState::eat_ident(self : ParseState) -> String? {
  match self.peek() {
    Some(IDENT(name)) => {
      self.advance()
      Some(name)
    }
    _ => None
  }
}

///|
/// Checks if current token is LP and consumes it.
fn ParseState::eat_lp(self : ParseState) -> Bool {
  match self.peek() {
    Some(LP) => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
/// Checks if current token is RP and consumes it.
fn ParseState::eat_rp(self : ParseState) -> Bool {
  match self.peek() {
    Some(RP) => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
/// Checks if current token is LB and consumes it.
fn ParseState::eat_lb(self : ParseState) -> Bool {
  match self.peek() {
    Some(LB) => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
/// Checks if current token is RB and consumes it.
fn ParseState::eat_rb(self : ParseState) -> Bool {
  match self.peek() {
    Some(RB) => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
/// Checks if current token is STAR and consumes it.
fn ParseState::eat_star(self : ParseState) -> Bool {
  match self.peek() {
    Some(STAR) => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
/// Checks if current token is PLUS and consumes it.
fn ParseState::eat_plus(self : ParseState) -> Bool {
  match self.peek() {
    Some(PLUS) => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
/// Checks if current token is Q (?) and consumes it.
fn ParseState::eat_q(self : ParseState) -> Bool {
  match self.peek() {
    Some(Q) => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
/// Checks if current token is BAR and consumes it.
fn ParseState::eat_bar(self : ParseState) -> Bool {
  match self.peek() {
    Some(BAR) => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
/// Checks if current token is COLON and consumes it.
fn ParseState::eat_colon(self : ParseState) -> Bool {
  match self.peek() {
    Some(COLON) => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
/// Checks if current token is AMP (&) and consumes it.
fn ParseState::eat_amp(self : ParseState) -> Bool {
  match self.peek() {
    Some(AMP) => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
/// Checks if current token is EXCL (!) and consumes it.
fn ParseState::eat_excl(self : ParseState) -> Bool {
  match self.peek() {
    Some(EXCL) => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
/// Checks if current token is SLASH (/) and consumes it.
fn ParseState::eat_slash(self : ParseState) -> Bool {
  match self.peek() {
    Some(SLASH) => {
      self.advance()
      true
    }
    _ => false
  }
}

///|
/// Returns true if current token is a stop token (RP, RB, BAR, SLASH).
fn ParseState::is_stop_token(self : ParseState) -> Bool {
  match self.peek() {
    Some(RP) | Some(RB) | Some(BAR) | Some(SLASH) => true
    _ => false
  }
}

///|
/// Checks if a character is a valid identifier start.
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
/// Checks if a character is a valid identifier continuation.
fn is_ident_char(c : Char) -> Bool {
  is_ident_start(c) || (c >= '0' && c <= '9')
}

///|
/// Checks if a character is whitespace.
fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// Removes comments from a line (everything after #).
fn remove_comment(line : String) -> String {
  let chars = line.to_array()
  let result : Array[Char] = []
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '#' {
      break
    }
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Preprocesses the input string: removes comments and empty lines.
fn preprocess(s : String) -> String {
  let lines = s.split("\n")
  let buf = StringBuilder::new(size_hint=s.length())
  let mut first = true
  for line in lines {
    let line_str = line.to_string()
    let cleaned = remove_comment(line_str)
    let trimmed = cleaned.trim()
    if trimmed.length() > 0 {
      if !first {
        buf.write_string("\n")
      }
      buf.write_string(cleaned)
      first = false
    }
  }
  buf.to_string()
}

///|
/// Tokenizes a PEG expression string into grammar tokens.
fn tokenize_expr(s : String) -> Array[GrammarToken] raise {
  let preprocessed = preprocess(s)
  let chars = preprocessed.to_array()
  let tokens : Array[GrammarToken] = []
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if is_whitespace(c) {
      i += 1
      continue
    }
    if c == '(' {
      tokens.push(LP)
      i += 1
      continue
    }
    if c == ')' {
      tokens.push(RP)
      i += 1
      continue
    }
    if c == '[' {
      tokens.push(LB)
      i += 1
      continue
    }
    if c == ']' {
      tokens.push(RB)
      i += 1
      continue
    }
    if c == '*' {
      tokens.push(STAR)
      i += 1
      continue
    }
    if c == '+' {
      tokens.push(PLUS)
      i += 1
      continue
    }
    if c == '?' {
      tokens.push(Q)
      i += 1
      continue
    }
    if c == '|' {
      tokens.push(BAR)
      i += 1
      continue
    }
    if c == ':' {
      tokens.push(COLON)
      i += 1
      continue
    }
    if c == '&' {
      tokens.push(AMP)
      i += 1
      continue
    }
    if c == '!' {
      tokens.push(EXCL)
      i += 1
      continue
    }
    if c == '/' {
      tokens.push(SLASH)
      i += 1
      continue
    }
    if is_ident_start(c) {
      let start = i
      while i < chars.length() && is_ident_char(chars[i]) {
        i += 1
      }
      let ident_chars : Array[Char] = []
      for j = start; j < i; j = j + 1 {
        ident_chars.push(chars[j])
      }
      tokens.push(IDENT(String::from_array(ident_chars)))
      continue
    }
    raise @builtin.Failure("Bad grammar char: \{c}")
  }
  tokens
}

///|
/// Parses a primary expression (identifier, label, parenthesized group, bracketed optional, or predicate).
fn parse_primary(state : ParseState) -> Node? raise {
  // Try And-predicate (&e)
  if state.eat_amp() {
    let child = parse_primary(state)
    match child {
      Some(node) => return Some(Node::And(node))
      None => raise @builtin.Failure("& without expression")
    }
  }
  // Try Not-predicate (!e)
  if state.eat_excl() {
    let child = parse_primary(state)
    match child {
      Some(node) => return Some(Node::Not(node))
      None => raise @builtin.Failure("! without expression")
    }
  }
  // Try parenthesized group
  if state.eat_lp() {
    let inner = parse_choice(state)
    if !state.eat_rp() {
      raise @builtin.Failure("missing )")
    }
    return Some(inner)
  }
  // Try bracketed optional (deprecated: use e? instead)
  if state.eat_lb() {
    state.warn_deprecated("deprecated: use 'e?' instead of '[e]' for optional")
    let inner = parse_choice(state)
    if !state.eat_rb() {
      raise @builtin.Failure("missing ]")
    }
    return Some(Node::Optional(inner))
  }
  // Try identifier (possibly labeled)
  match state.eat_ident() {
    Some(ident) =>
      // Check for label
      if state.eat_colon() {
        let child = parse_primary(state)
        match child {
          Some(child_node) => Some(Node::Label(ident, child_node))
          None => raise @builtin.Failure("label without target")
        }
      } else {
        Some(Node::Sym(ident))
      }
    None => None
  }
}

///|
/// Parses a postfix expression (primary with optional *, +, or ?).
fn parse_postfix(state : ParseState) -> Node? raise {
  let prim = parse_primary(state)
  match prim {
    None => None
    Some(node) =>
      if state.eat_star() {
        Some(Node::Star(node))
      } else if state.eat_plus() {
        Some(Node::Plus(node))
      } else if state.eat_q() {
        Some(Node::Optional(node))
      } else {
        Some(node)
      }
  }
}

///|
/// Parses a sequence of expressions.
fn parse_seq(state : ParseState) -> Node raise {
  let items : Array[Node] = []
  while state.has_more() && !state.is_stop_token() {
    let item = parse_postfix(state)
    match item {
      Some(node) => items.push(node)
      None => break
    }
  }
  if items.length() == 0 {
    Node::Empty
  } else if items.length() == 1 {
    items[0]
  } else {
    Node::Seq(items)
  }
}

///|
/// Parses a choice expression (alternatives separated by / or |).
/// PEG standard uses /. The | operator is deprecated.
fn parse_choice(state : ParseState) -> Node raise {
  let alts : Array[Node] = []
  alts.push(parse_seq(state))
  while true {
    if state.eat_slash() {
      alts.push(parse_seq(state))
    } else if state.eat_bar() {
      state.warn_deprecated(
        "deprecated: use '/' instead of '|' for choice operator",
      )
      alts.push(parse_seq(state))
    } else {
      break
    }
  }
  if alts.length() == 1 {
    alts[0]
  } else {
    Node::Choice(alts)
  }
}

///|
/// Parses a PEG expression string into a Node AST.
pub fn parse_expr(s : String) -> Node raise {
  let (node, _) = parse_expr_with_warnings(s)
  node
}

///|
/// Parses a PEG expression string into a Node AST, returning deprecation warnings.
pub fn parse_expr_with_warnings(s : String) -> (Node, Array[String]) raise {
  let tokens = tokenize_expr(s)
  let state = ParseState::new(tokens)
  let result = parse_choice(state)
  if state.has_more() {
    raise @builtin.Failure("Unused grammar tokens at position \{state.pos}")
  }
  (result, state.warnings)
}
