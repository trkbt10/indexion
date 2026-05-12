///|
/// Result of a pattern match attempt.
/// Contains whether the match succeeded, the end position, and the matched text.
pub struct MatchResult {
  matched : Bool
  end_pos : Int
  text : String
}

///|
/// Regex match with capture groups.
pub struct CapturedMatch {
  start_pos : Int
  end_pos : Int
  text : String
  captures : Array[String]
}

///|
/// Creates a successful match result.
pub fn MatchResult::success(end_pos : Int, text : String) -> MatchResult {
  { matched: true, end_pos, text }
}

///|
/// Creates a failed match result.
pub fn MatchResult::failure() -> MatchResult {
  { matched: false, end_pos: 0, text: "" }
}

///|
/// Mutable capture group state for tracking during matching.
pub struct CaptureState {
  /// (start, end) positions for each capture group, indexed by group number (1-based).
  groups : Array[(Int, Int)]
  /// Total number of capture groups in the pattern.
  count : Int
}

///|
pub fn CaptureState::new(count : Int) -> CaptureState {
  let groups : Array[(Int, Int)] = Array::make(count + 1, (-1, -1))
  { groups, count }
}

///|
pub fn CaptureState::set(
  self : CaptureState,
  index : Int,
  start : Int,
  end : Int,
) -> Unit {
  if index >= 0 && index < self.groups.length() {
    self.groups[index] = (start, end)
  }
}

///|
pub fn CaptureState::reset(self : CaptureState, index : Int) -> Unit {
  if index >= 0 && index < self.groups.length() {
    self.groups[index] = (-1, -1)
  }
}

///|
/// Get captured text for group N from input chars.
pub fn CaptureState::get_group_text(
  self : CaptureState,
  index : Int,
  input_chars : Array[Char],
) -> String? {
  if index <= 0 || index > self.count {
    return None
  }
  let (start, end) = self.groups[index]
  if start < 0 || end < 0 {
    return None
  }
  let chars : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    if i < input_chars.length() {
      chars.push(input_chars[i])
    }
  }
  Some(String::from_array(chars))
}

///|
/// Parsed pattern element for internal use.
priv enum PatternElement {
  Literal(Char)
  CharClass(Array[(Char, Char)], Bool) // ranges, negated
  AnyChar // .
  Escape(Char) // \s, \w, \d, \S, \W, \D, etc.
  WordBoundary // \b - zero-width assertion
  NonWordBoundary // \B - zero-width assertion
  StartAnchor // ^ - start of string/line
  EndAnchor // $ - end of string/line
  StringStart // \A - absolute start of string
  StringEnd // \z - absolute end of string
  Group(Array[QuantifiedElement], Int?) // elements, capture_index (None = non-capturing)
  Alternation(Array[Array[QuantifiedElement]])
  Lookahead(Array[QuantifiedElement], Bool) // elements, positive (true=(?=...), false=(?!...))
}

///|
/// Quantifier type for pattern elements.
priv enum Quantifier {
  One
  ZeroOrMore // *
  OneOrMore // +
  ZeroOrOne // ?
  Exactly(Int) // {n}
  AtLeast(Int) // {n,}
  Between(Int, Int) // {n,m}
}

///|
/// If an `Escape(c)` element matches exactly one literal character — i.e.
/// `c` is NOT a regex shortcut class like `\s`/`\S`/`\d`/`\D`/`\w`/`\W` —
/// return that character. Returns `None` for shortcut classes, which
/// match a set of characters rather than a single literal.
///
/// Centralizes the regex engine's "which escapes denote a single literal
/// char" knowledge in one place so the matcher's fast-path scanners and
/// the introspection API (`CompiledPattern::literal_text`) cannot drift
/// apart.
fn escape_literal_char(escape_char : Char) -> Char? {
  match escape_char {
    's' | 'S' | 'd' | 'D' | 'w' | 'W' => None
    'n' => Some('\n')
    'r' => Some('\r')
    't' => Some('\t')
    _ => Some(escape_char)
  }
}

///|
/// Pattern element with quantifier.
priv struct QuantifiedElement {
  element : PatternElement
  quantifier : Quantifier
  lazy_ : Bool
}

///|
/// CompiledPattern stores parsed regex elements for repeated matching.
pub(all) struct CompiledPattern {
  priv alternatives : Array[Array[QuantifiedElement]]
  priv case_insensitive : Bool
  /// Optional first char filter for quick rejection.
  priv first_char_filter : FirstCharFilter
  /// Number of capture groups in the pattern.
  priv capture_count : Int
  /// True if all alternatives start with \b (word boundary).
  priv requires_word_boundary_start : Bool
}

///|
/// Returns the number of capture groups in the pattern.
pub fn CompiledPattern::get_capture_count(self : CompiledPattern) -> Int {
  self.capture_count
}

///|
/// First character filter for quick pattern rejection.
priv enum FirstCharFilter {
  Any // Pattern can start with any character
  Literal(Char) // Pattern must start with this exact char
  LiteralCI(Char, Char) // Case-insensitive: lower and upper
  CharClass(Array[(Char, Char)], Bool) // (ranges, negated)
}

///|
/// Mutable state for pattern parsing -- tracks capture group numbering.
priv struct ParseContext {
  mut next_capture : Int
}

///|
fn ParseContext::new() -> ParseContext {
  { next_capture: 1 }
}

///|
fn ParseContext::alloc_capture(self : ParseContext) -> Int {
  let idx = self.next_capture
  self.next_capture += 1
  idx
}
