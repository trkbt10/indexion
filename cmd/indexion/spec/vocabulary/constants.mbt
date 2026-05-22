///|
let vocabulary_report_version : String = "kgf-vocabulary-v1"

///|
let role_source : String = "source"

///|
let role_target : String = "target"

///|
let direction_both : String = "both"

///|
let direction_source_to_target : String = "source-to-target"

///|
let direction_target_to_source : String = "target-to-source"

///|
let direction_alias_coverage : String = "coverage"

///|
let direction_alias_drift : String = "drift"

///|
let output_format_text : String = "text"

///|
let output_format_json : String = "json"

///|
let output_format_markdown : String = "md"

///|
let term_kind_interface : String = "interface"

///|
let term_kind_member : String = "member"

///|
let term_kind_symbol : String = "symbol"

///|
let term_kind_literal : String = "literal"

///|
let term_kind_word : String = "word"

///|
let issue_classification_report_precision : String = "report-precision-candidate"

///|
let issue_classification_output_noise : String = "output-noise-candidate"

///|
let issue_classification_unresolved : String = "unresolved"

///|
let issue_reason_same_value_different_kind : String = "same-normalized-value-different-kind"

///|
let issue_reason_probable_name_alias : String = "probable-name-alias"

///|
let issue_reason_short_grammar_literal : String = "short-grammar-literal"

///|
let issue_reason_no_target_evidence : String = "no-target-evidence"

///|
fn normalize_direction(direction : String) -> String {
  match direction {
    source if source == role_source || source == direction_alias_coverage =>
      direction_source_to_target
    target if target == role_target || target == direction_alias_drift =>
      direction_target_to_source
    value if value == direction_source_to_target => direction_source_to_target
    value if value == direction_target_to_source => direction_target_to_source
    _ => direction_both
  }
}

///|
fn direction_checks_missing(direction : String) -> Bool {
  direction == direction_both || direction == direction_source_to_target
}

///|
fn direction_checks_drift(direction : String) -> Bool {
  direction == direction_both || direction == direction_target_to_source
}

///|
fn direction_passes(
  direction : String,
  missing_count : Int,
  drift_count : Int,
) -> Bool {
  (!direction_checks_missing(direction) || missing_count == 0) &&
  (!direction_checks_drift(direction) || drift_count == 0)
}
