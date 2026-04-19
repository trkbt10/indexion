///|
/// Reserved label names used in the PEG evaluator → consumer contract.
///
/// Every underscore-prefixed key that the evaluator writes to, or that a
/// consumer (semantics, declarations extractor, docgen, attr DSL) reads
/// from, is declared here exactly once. Referencing these constants instead
/// of string literals keeps the wire format in sync across packages.

///|
/// Primary text accumulator — the concatenated source span of every token
/// consumed while the rule was matching. Exposed on the final label map.
pub const META_TEXT : String = "_text"

///|
/// Token index (inclusive) where a rule match began.
pub const META_START_TOK : String = "_start_tok"

///|
/// Token index (exclusive) where a rule match ended.
pub const META_END_TOK : String = "_end_tok"

///|
/// Text of the most recently consumed token within the current rule.
pub const META_LAST : String = "_last"

///|
/// Source position of the most recently consumed token (character offset).
pub const META_LAST_POS : String = "_last_pos"

///|
/// Length (in characters) of the most recently consumed token.
pub const META_LAST_LEN : String = "_last_len"

///|
/// Suffix appended to a labeled capture's name to expose its text span.
/// For a capture `foo:Rule`, the text span is published as `foo_text`.
pub const META_TEXT_SUFFIX : String = "_text"

///|
/// Suffix appended to a labeled capture's name to expose the `_last_pos`
/// of the captured sub-tree (e.g. `foo_pos`).
pub const META_POS_SUFFIX : String = "_pos"

///|
/// Suffix appended to a labeled capture's name to expose the `_last_len`
/// of the captured sub-tree (e.g. `foo_len`).
pub const META_LEN_SUFFIX : String = "_len"
