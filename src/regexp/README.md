# regexp

## API

- **`try_collect_repeat_positions_fast`** (Function) — Fast path for repeated alternation: (A|B|C)* or (A|B|C)+
- **`match_elements_backtrack`** (Function) — Matches a sequence of elements with backtracking support.
- **`extract_first_char_ranges`** (Function) — Extracts first char ranges from a single alternative's first consuming element.
- **`quantifier_bounds`** (Function) — Returns quantifier min/max bounds. max_possible is the number of chars that
- **`match_pattern`** (Function) — Matches a pattern against the input starting at the given position.
- **`sequence_fixed_width`** (Function) — Returns the fixed character width of a simple-element sequence,
- **`matches_at`** (Function) — Checks if a pattern matches at the start of the input at the given position.
- **`find_first_consuming_element`** (Function) — Finds the first consuming element in an element sequence,
- **`match_quantified`** (Function) — Matches a quantified element against the input starting at pos.
- **`MatchResult`** (Struct) — Result of a pattern match attempt.
- **`is_simple_element`** (Function) — Checks if a PatternElement can be matched with match_char (single char, no recursion).
- **`match_alternation`** (Function) — Matches alternation (a|b|c pattern) -- legacy, returns first greedy match.
- **`parse_unicode_escape`** (Function) — Parses a Unicode escape \uXXXX from the pattern. Returns (char, new_pos).
- **`match_alternation_positions`** (Function) — Returns all possible end positions for an alternation with a quantifier.
- **`is_word_char`** (Function) — Checks if a character is a word character (alphanumeric or underscore).
- **`count_simple_matches`** (Function) — Counts how many consecutive characters match a simple element from pos.
- **`build_input_chars`** (Function) — Builds a char array once for repeated indexed access during matching.
- **`try_match_simple_sequence`** (Function) — Matches a fixed-width sequence of simple elements without recursion.
- **`is_at_word_boundary_with_chars`** (Function) — Checks if position is at a word boundary using prebuilt input chars.
- **`ParseContext`** (Struct) — Mutable state for pattern parsing -- tracks capture group numbering.
- **`CompiledPattern`** (Struct) — CompiledPattern stores parsed regex elements for repeated matching.
- **`match_group`** (Function) — Matches a group of elements (legacy -- returns first greedy match).
- **`match_compiled_end_pos_with_chars`** (Function) — Matches a compiled pattern against the input at the given position.
- **`match_compiled_with_chars`** (Function) — Matches a compiled pattern against the input at the given position.
- **`match_group_positions`** (Function) — Returns all possible end positions for a group with a quantifier.
- **`enumerate_group_end_positions`** (Function) — Enumerates all possible end positions for a single group match.
- **`parse_pattern_ctx`** (Function) — Parses the pattern string into a list of quantified elements.
- **`get_char_at`** (Function) — Gets a character from a string at the given index safely.
- **`CaptureState`** (Struct) — Mutable capture group state for tracking during matching.
- **`extract_first_char_filter`** (Function) — Extracts a first char filter from compiled alternatives.
- **`match_char`** (Function) — Matches a single character against a pattern element.
- **`match_simple`** (Function) — Matches a simple element (non-group) with quantifier.
- **`get_capture_count`** (Function) — Returns the number of capture groups in the pattern.
- **`FirstCharFilter`** (Enum) — First character filter for quick pattern rejection.
- **`check_first_char_filter`** (Function) — Checks if a character passes the first char filter.
- **`parse_char_class`** (Function) — Parses a character class like [a-z], [0-9], [^abc].
- **`is_whitespace`** (Function) — Checks if a character is a whitespace character.
- **`get_group_text`** (Function) — Get captured text for group N from input chars.
- **`compile_pattern`** (Function) — Compiles a pattern once for repeated matching.
- **`parse_brace_quantifier`** (Function) — Parses a brace quantifier {n}, {n,}, {n,m}.
- **`get_input_char`** (Function) — Gets a character from prebuilt input chars.
- **`split_by_alternation`** (Function) — Splits a pattern by top-level alternation.
- **`PatternElement`** (Enum) — Parsed pattern element for internal use.
- **`Quantifier`** (Enum) — Quantifier type for pattern elements.
- **`success`** (Function) — Creates a successful match result.
- **`to_lower`** (Function) — Converts a character to lowercase.
- **`is_digit`** (Function) — Checks if a character is a digit.
- **`QuantifiedElement`** (Struct) — Pattern element with quantifier.
- **`CapturedMatch`** (Struct) — Regex match with capture groups.
- **`failure`** (Function) — Creates a failed match result.
- **`new`** (Function) — 


- **`alloc_capture`** (Function) — 


- **`captured_match_from_state`** (Function) — 


- **`find_pattern_captures`** (Function) — 


- **`set`** (Function) — 


- **`reset`** (Function) —
