///|
/// Compiles a pattern once for repeated matching.
pub fn compile_pattern(
  pattern : String,
  case_insensitive? : Bool = false,
) -> CompiledPattern? {
  let ctx = ParseContext::new()
  let alternatives = split_by_alternation(pattern)
  let compiled_alts : Array[Array[QuantifiedElement]] = []
  for alt in alternatives {
    match parse_pattern_ctx(alt, ctx) {
      Some(elements) => compiled_alts.push(elements)
      None => return None
    }
  }
  let first_char_filter = extract_first_char_filter(
    compiled_alts, case_insensitive,
  )
  let capture_count = ctx.next_capture - 1
  // Check if all alternatives start with \b
  let requires_word_boundary_start = compiled_alts.length() > 0 &&
    compiled_alts
    .iter()
    .all(fn(alt) { alt.length() > 0 && alt[0].element is WordBoundary })
  Some({
    alternatives: compiled_alts,
    case_insensitive,
    first_char_filter,
    capture_count,
    requires_word_boundary_start,
  })
}

///|
/// Matches a compiled pattern against the input at the given position.
fn match_compiled_with_chars(
  compiled : CompiledPattern,
  input : String,
  input_chars : Array[Char],
  pos : Int,
) -> MatchResult {
  match match_compiled_end_pos_with_chars(compiled, input_chars, pos) {
    Some(end_pos) =>
      MatchResult::success(end_pos, input[pos:end_pos].to_string())
    None => MatchResult::failure()
  }
}

///|
/// Matches a pattern against the input starting at the given position.
/// Returns the match result with the end position and matched text.
pub fn match_pattern(
  pattern : String,
  input : String,
  pos : Int,
  case_insensitive? : Bool = false,
) -> MatchResult {
  let input_chars = build_input_chars(input)
  match compile_pattern(pattern, case_insensitive~) {
    Some(compiled) =>
      match_compiled_with_chars(compiled, input, input_chars, pos)
    None => MatchResult::failure()
  }
}

///|
/// Checks if a pattern matches at the start of the input at the given position.
/// This is a convenience wrapper around match_pattern.
pub fn matches_at(
  pattern : String,
  input : String,
  pos : Int,
  case_insensitive? : Bool = false,
) -> Bool {
  match_pattern(pattern, input, pos, case_insensitive~).matched
}

///|
fn captured_match_from_state(
  start_pos : Int,
  end_pos : Int,
  input : String,
  input_chars : Array[Char],
  captures : CaptureState,
) -> CapturedMatch {
  let groups : Array[String] = []
  for i = 1; i <= captures.count; i = i + 1 {
    groups.push(captures.get_group_text(i, input_chars).unwrap_or(""))
  }
  {
    start_pos,
    end_pos,
    text: input[start_pos:end_pos].to_string(),
    captures: groups,
  }
}

///|
pub fn find_pattern_captures(
  pattern : String,
  input : String,
  case_insensitive? : Bool = false,
) -> Array[CapturedMatch] {
  let matches : Array[CapturedMatch] = []
  let input_chars = build_input_chars(input)
  let compiled = match compile_pattern(pattern, case_insensitive~) {
    Some(value) => value
    None => return matches
  }
  let input_len = input_chars.length()
  let filter = compiled.first_char_filter
  let wb_required = compiled.requires_word_boundary_start
  let mut pos = 0
  while pos < input_len {
    // Inline first char filter for fast scan skip
    if !check_first_char_filter(filter, input_chars[pos]) {
      pos += 1
      continue
    }
    // Skip positions that aren't at a word boundary when pattern requires it
    if wb_required && !is_at_word_boundary_with_chars(input_chars, pos) {
      pos += 1
      continue
    }
    let captures = CaptureState::new(compiled.capture_count)
    match
      match_compiled_end_pos_with_chars(
        compiled,
        input_chars,
        pos,
        captures=Some(captures),
      ) {
      Some(end_pos) => {
        matches.push(
          captured_match_from_state(pos, end_pos, input, input_chars, captures),
        )
        pos = if end_pos > pos { end_pos } else { pos + 1 }
      }
      None => pos += 1
    }
  }
  matches
}
