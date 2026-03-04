///|
/// Bracket pairing for fast balanced matching.
/// Pre-computes matching bracket pairs in O(n) to avoid deep recursion.

///|
/// BracePairs maps opening bracket positions to closing bracket positions.
pub struct BracePairs {
  /// Maps token index of open bracket to token index of close bracket
  pairs : Array[Int]
}

///|
/// Bracket type for matching.
priv enum BracketType {
  Brace // { }
  Paren // ( )
  Bracket // [ ]
}

///|
/// Returns bracket type and whether it's opening or closing.
fn get_bracket_info(kind : String) -> (BracketType, Bool)? {
  match kind {
    "LBRACE" => Some((Brace, true))
    "RBRACE" => Some((Brace, false))
    "LPAREN" => Some((Paren, true))
    "RPAREN" => Some((Paren, false))
    "LBRACKET" => Some((Bracket, true))
    "RBRACKET" => Some((Bracket, false))
    _ => None
  }
}

///|
/// Computes bracket pairs from tokens in O(n).
/// Returns array where pairs[i] = j means token[i] opens and token[j] closes.
/// pairs[i] = -1 means no matching bracket found.
pub fn compute_brace_pairs(tokens : Array[@types.Tok]) -> BracePairs {
  let n = tokens.length()
  let pairs : Array[Int] = Array::make(n, -1)

  // Stack of (position, bracket_type)
  let stack : Array[(Int, BracketType)] = []

  for i = 0; i < n; i = i + 1 {
    let kind = tokens[i].kind
    match get_bracket_info(kind) {
      Some((bracket_type, is_open)) =>
        if is_open {
          stack.push((i, bracket_type))
        } else {
          // Find matching open bracket
          let mut found = false
          for j = stack.length() - 1; j >= 0 && not(found); j = j - 1 {
            let (open_pos, open_type) = stack[j]
            match (open_type, bracket_type) {
              (Brace, Brace) | (Paren, Paren) | (Bracket, Bracket) => {
                pairs[open_pos] = i
                pairs[i] = open_pos
                // Remove from stack
                let _ = stack.pop()
                found = true
              }
              _ => ()
            }
          }
        }
      None => ()
    }
  }
  { pairs, }
}

///|
/// Gets the matching close bracket position for an open bracket.
/// Returns None if not an open bracket or no match found.
pub fn BracePairs::get_close(self : BracePairs, open_pos : Int) -> Int? {
  if open_pos >= 0 && open_pos < self.pairs.length() {
    let close = self.pairs[open_pos]
    if close > open_pos {
      Some(close)
    } else {
      None
    }
  } else {
    None
  }
}

///|
/// Checks if position is an opening bracket with a valid pair.
pub fn BracePairs::is_balanced_open(self : BracePairs, pos : Int) -> Bool {
  match self.get_close(pos) {
    Some(_) => true
    None => false
  }
}
