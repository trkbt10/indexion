///|
/// # Per-language transpile specs (lift / lower)
///
/// To support every (source × target) language pair without writing N×M
/// per-pair files, each language ships ONE spec file at
/// `kgf-transpile/<lang>.json` declaring:
///
/// - `lift`: how the language's KGF events map into a canonical IR
///   (rule renames, scalar substitutions, type wraps).
/// - `lower`: how to emit target code from canonical IR events
///   (emit templates, scalar lowering, comment prefix, preamble).
///
/// Transpilation between source A and target B = `A.lift` + `B.lower`.
/// Adding a 9th language is one new spec file, zero engine changes.
///
/// Discovery: callers go through `find_spec(language)` which scans
/// `kgf-transpile/` and matches by the spec's `language` field — never
/// by filename pattern.

///|
/// One source-suffix → target-template type-wrap rule. Used in `lift` to
/// convert source generic syntax (`T[]`) to canonical IR (`Array<T>`).
/// `target_template` uses `%s` as the inner-type placeholder.
pub struct TypeWrap {
  source_suffix : String
  target_template : String
} derive(Eq, Debug, FromJson, ToJson)

///|
pub fn TypeWrap::source_suffix(self : TypeWrap) -> String {
  self.source_suffix
}

///|
pub fn TypeWrap::target_template(self : TypeWrap) -> String {
  self.target_template
}

///|
/// One `collect_inner_as` rule: aggregate inner events of a given KGF rule
/// into a label on the parent IR event. The separator between rendered
/// children is target-specific and comes from `lower.collect_separators`
/// (keyed by `label`), NOT from this struct — different targets need
/// different separators (Rust needs `,\n    ` between struct fields,
/// MoonBit just newline).
pub struct CollectInnerAs {
  /// KGF rule name to collect (e.g. `PropertySig`, `Param`).
  rule : String
  /// Label name on the parent IR event to populate (e.g. `fields`, `params`).
  label : String
} derive(Eq, Debug, FromJson, ToJson)

///|
/// One `extract_text` rule: derive a label by isolating a fragment of the
/// parent's `_text`. Currently expressed as a simple "between two literals"
/// extractor — sufficient for `type X = <rhs>;` and similar shapes.
pub struct ExtractText {
  /// Label name on the parent IR event to populate.
  label : String
  /// Take everything AFTER this literal in `_text`.
  after : String
  /// And BEFORE this literal. Empty = end of string.
  before : String
  /// Trim ASCII whitespace from the result.
  trim : Bool
  /// If set true: after lift+lower rewriting, if the result still contains
  /// `|` (an unhandled union), keep only the first `|`-separated part.
  /// Used to handle mixed type+literal unions (`TodoStatus | "all"`)
  /// without leaving target-invalid syntax. The original source is still
  /// preserved via `source_intent_comment` so a later agent can refine.
  simplify_unions : Bool?
} derive(Eq, Debug, FromJson, ToJson)

///|
/// One conditional-lift rule: when the parent's `_text` matches a simple
/// shape, override the default `rule_lifts` mapping and (optionally)
/// split the text into a list label.
///
/// The shape predicate is intentionally minimal. Currently supported:
///
/// - `string_literal_union` — every `|`-separated token (after stripping
///   leading/trailing whitespace and surrounding `"`/`'`) is an
///   identifier-only string. Used to lift TS `type X = "a" | "b" | "c"`
///   into `IREnum` rather than `IRTypeAlias`.
///
/// On match, `lift_to` overrides the default IR rule, and
/// `split_label_capitalized` (if set) populates a label with the
/// capitalized variant names joined by the lower spec's
/// `collect_separators[<label>]`.
pub struct ConditionalLift {
  predicate : String
  lift_to : String
  split_label_capitalized : String?
} derive(Eq, Debug, FromJson, ToJson)

///|
/// Structural rules attached to a SOURCE KGF rule. Applied at lower time
/// using both `lift` (to know inner-event mappings) and the IR event stream.
pub struct StructuralRule {
  /// `<SiblingRule>.<label>` — copy a label from a sibling event whose
  /// token range is contained in this event's range. Empty = no-op.
  id_from : String?
  /// Inner-event aggregations to apply.
  collect_inner_as : Array[CollectInnerAs]?
  /// Text-extraction rules to apply on `_text`.
  extract_text : Array[ExtractText]?
  /// Conditional-lift overrides applied AFTER the default rule rename.
  /// First matching rule wins; the IR event's rule is replaced with
  /// `lift_to` and any `split_label_capitalized` is populated. The
  /// matching predicate operates on the parent's `rhs` label
  /// (populated by an earlier `extract_text` rule).
  conditional_lifts : Array[ConditionalLift]?
  /// Optional comment template emitted before the event's main template
  /// when something about the source could not be cleanly translated.
  /// Intended for preserving source intent (`// SOURCE: ...`) so later
  /// agents can finish the port. Renders the same `{{...}}` placeholders
  /// as the main template plus `{{comment_prefix}}`.
  source_intent_comment : String?
} derive(Debug, FromJson, ToJson)

///|
/// Lift section: how a language's KGF events map to canonical IR events.
pub struct LiftSpec {
  /// Source-language scalar (e.g. `number`) → canonical IR scalar (e.g. `Float`).
  scalars : Map[String, String]
  /// Generic syntax patterns (e.g. `T[]` → `Array<%s>`).
  type_wraps : Array[TypeWrap]
  /// KGF rule name → canonical IR rule name (e.g. `TypeDecl` → `IREnum`).
  rule_lifts : Map[String, String]
  /// Per-source-rule structural derivation rules. Applied at lower time.
  /// Optional in the spec file; absent = no structural rules.
  structural_rules : Map[String, StructuralRule]?
  /// Source module path → canonical module category. Used to lift import
  /// statements with known semantics (`node:fs` → `fs`,
  /// `node:crypto` → `crypto`). Tied to `lower.module_aliases` on the
  /// target side so the import can be rewritten end-to-end.
  /// Users extend this to add their own libraries.
  module_aliases : Map[String, String]?
  /// `<canonical-module>.<source-symbol>` → canonical symbol name.
  /// Lifts known library symbols to canonical names so the lower can map
  /// them to its own equivalents (e.g. `fs.readFileSync` → `fs.read_to_string`).
  symbol_aliases : Map[String, String]?
  /// The opening and closing delimiters that surround a function body in
  /// the source language. Set to `["{", "}"]` for C-family / ML-family
  /// languages whose KGF spec emits `body_pos` (the position of the closing
  /// delimiter). Absent / null for indent-based languages (Python) whose
  /// bodies aren't bracketed and where KGF doesn't emit `body_pos`.
  ///
  /// Used by the driver to:
  /// - locate the start of the body via balanced search back from `body_pos`
  /// - emit a delimiter-stripped `body_inner_text` label so indent-based
  ///   targets can render bodies without literal braces.
  body_delimiters : Array[String]?
  /// Source-language-specific body normalization rules. Run during lift
  /// against every non-internal string label, BEFORE structural rules
  /// and BEFORE the target lower sees any text. Each entry is a
  /// `(pattern, replacement)` regex rule with `$1..$9` backref support.
  ///
  /// This is where source-only syntax that the canonical IR does not
  /// carry should be stripped: TS's `===`/`!==` strict-equality, `??`
  /// nullish coalescing, template-literal backticks, the `;` statement
  /// terminator, etc. Target specs MUST NOT contain source-specific
  /// patterns — that would re-introduce the N×M coupling that the
  /// lift/lower split exists to eliminate.
  regex_replace : Array[RegexReplace]?
} derive(Debug, FromJson, ToJson)

///|
pub fn LiftSpec::scalars(self : LiftSpec) -> Map[String, String] {
  self.scalars
}

///|
pub fn LiftSpec::type_wraps(self : LiftSpec) -> Array[TypeWrap] {
  self.type_wraps
}

///|
pub fn LiftSpec::rule_lifts(self : LiftSpec) -> Map[String, String] {
  self.rule_lifts
}

///|
pub fn LiftSpec::structural_rules(
  self : LiftSpec,
) -> Map[String, StructuralRule] {
  match self.structural_rules {
    Some(m) => m
    None => Map([])
  }
}

///|
pub fn LiftSpec::module_aliases(self : LiftSpec) -> Map[String, String] {
  match self.module_aliases {
    Some(m) => m
    None => Map([])
  }
}

///|
pub fn LiftSpec::symbol_aliases(self : LiftSpec) -> Map[String, String] {
  match self.symbol_aliases {
    Some(m) => m
    None => Map([])
  }
}

///|
pub fn LiftSpec::regex_replace(self : LiftSpec) -> Array[RegexReplace] {
  match self.regex_replace {
    Some(a) => a
    None => []
  }
}

///|
/// `(open, close)` body delimiter pair from the spec, or `None` when the
/// source language doesn't use paired delimiters (indent-based languages).
/// Validates that the spec declared exactly two single-character entries.
pub fn LiftSpec::body_delimiter_chars(self : LiftSpec) -> (Char, Char)? {
  match self.body_delimiters {
    Some(arr) =>
      if arr.length() == 2 && arr[0].length() == 1 && arr[1].length() == 1 {
        Some((arr[0].to_array()[0], arr[1].to_array()[0]))
      } else {
        None
      }
    None => None
  }
}

///|
/// Lower section: how to emit target code from canonical IR events.
pub struct LowerSpec {
  /// Canonical IR scalar (e.g. `Float`) → target-language scalar (e.g. `Double`).
  scalars : Map[String, String]
  /// Generic IR syntax patterns (e.g. `Array<%s>` → target wrap form).
  type_wraps : Array[TypeWrap]
  /// IR rule name → target emit template, with `{{label_name}}` placeholders.
  emit_templates : Map[String, String]
  /// IR rules to emit, in this order. Rules outside this list are skipped.
  emit_order : Array[String]
  /// Target-language comment prefix (e.g. `// `, `# `, `-- `). Used by
  /// `preamble_template` and `no_template_template` to stay language-agnostic.
  comment_prefix : String
  /// Top-of-file preamble. Placeholders: `{{comment_prefix}}`, `{{source_lang}}`,
  /// `{{target_lang}}`, `{{unresolved_marker}}`.
  preamble_template : String
  /// Fallback when an event has a rule that's in `emit_order` but missing
  /// from `emit_templates`. Placeholders: `{{comment_prefix}}`,
  /// `{{unresolved_marker}}`, `{{rule}}`.
  no_template_template : String
  /// Default body for `IRFn` events when the source has no body extracted —
  /// makes the emitted code compilable as a stub. Optional. Used by the
  /// engine to substitute into `{{body}}` for IRFn templates when no body
  /// was collected.
  default_body : String?
  /// Per-rendered-template substring replacements applied AFTER template
  /// rendering, BEFORE concatenation. Used to convert canonical IR syntax
  /// (e.g. `Array<T>`) to target-language syntax (e.g. `Array[T]` for
  /// moonbit / python / scala). NOT applied to the preamble or fallback
  /// template (those don't carry canonical IR syntax).
  ///
  /// Each entry: `{ "from": "<canonical>", "to": "<target>" }`.
  text_replace : Array[TextReplace]?
  /// Paired-delimiter rewrites (innermost-first). Used for canonical
  /// generic syntax → target form when it isn't a simple substring
  /// (e.g. `Optional<Todo>` → moonbit `Todo?`).
  text_replace_pairs : Array[TextReplacePair]?
  /// Regex-based body-level translations. Strip source-language-only
  /// syntax (TS type annotations on const declarations, `as` casts) so
  /// the verbatim `body_text_raw` parses on the target side.
  regex_replace : Array[RegexReplace]?
  /// Per-aggregation-label separators used by `collect_inner_as`. Keys
  /// match the `label` field on `CollectInnerAs` (e.g. `fields`, `params`,
  /// `variants`); values are the separator string to insert between
  /// rendered children. Different targets need different separators
  /// (Rust struct fields need `,\n    `, MoonBit struct fields newline only).
  /// Missing entry = empty separator.
  collect_separators : Map[String, String]?
  /// Canonical module category → target module path. Maps the canonical
  /// IR module names produced by `lift.module_aliases` onto the target
  /// language's import-path syntax (e.g. `fs` → `@fs` for moonbit,
  /// `fs` → `std::fs` for rust, `fs` → `os` for python's `os` module).
  /// Used by `IRImport` event templates via the `module_target` label.
  module_aliases : Map[String, String]?
  /// Casing style applied to variants produced by
  /// `lift.structural_rules.<rule>.conditional_lifts.split_label_capitalized`.
  /// Different targets follow different idioms: MoonBit/Rust use
  /// PascalCase enum variants, Swift uses lowercase, C/Python tend to
  /// SCREAMING_SNAKE. Values: `pascal` (default), `lower`, `screaming`.
  variant_case_style : String?
  /// `<canonical-module>.<canonical-symbol>` → target symbol name.
  /// Maps canonical library symbols to the target's equivalents
  /// (e.g. `fs.read_to_string` → `read_file_to_string` for moonbit's `@fs`).
  symbol_aliases : Map[String, String]?
} derive(Debug, FromJson, ToJson)

///|
/// One simple substring replacement rule for `lower.text_replace`.
pub struct TextReplace {
  from : String
  to : String
} derive(Eq, Debug, FromJson, ToJson)

///|
/// One regex-based rewrite. Used for body-level translation rules where
/// the source language carries syntax the target rejects (e.g. `: Type`
/// annotations on TS const declarations when emitting JavaScript). The
/// pattern is fed to `@regexp` and matches are replaced with `replacement`
/// across the whole label value.
pub struct RegexReplace {
  pattern : String
  replacement : String
} derive(Eq, Debug, FromJson, ToJson)

///|
/// One paired-delimiter rewrite. Matches `<open><inner><close>` and
/// replaces with `<template>` with `%s` substituted to `<inner>`.
///
/// Used to convert canonical IR generic syntax (`Optional<Todo>`) to
/// target syntax that isn't a simple substring substitution
/// (moonbit's `Todo?`, swift's `Todo?`, rust's `Option<Todo>`).
///
/// Matching is innermost-first so nested constructs (`Array<Optional<T>>`)
/// rewrite in stable order.
pub struct TextReplacePair {
  open : String
  close : String
  template : String
} derive(Eq, Debug, FromJson, ToJson)

///|
pub fn LowerSpec::scalars(self : LowerSpec) -> Map[String, String] {
  self.scalars
}

///|
pub fn LowerSpec::type_wraps(self : LowerSpec) -> Array[TypeWrap] {
  self.type_wraps
}

///|
pub fn LowerSpec::emit_templates(self : LowerSpec) -> Map[String, String] {
  self.emit_templates
}

///|
pub fn LowerSpec::emit_order(self : LowerSpec) -> Array[String] {
  self.emit_order
}

///|
pub fn LowerSpec::comment_prefix(self : LowerSpec) -> String {
  self.comment_prefix
}

///|
pub fn LowerSpec::preamble_template(self : LowerSpec) -> String {
  self.preamble_template
}

///|
pub fn LowerSpec::no_template_template(self : LowerSpec) -> String {
  self.no_template_template
}

///|
pub fn LowerSpec::default_body(self : LowerSpec) -> String? {
  self.default_body
}

///|
pub fn LowerSpec::text_replace(self : LowerSpec) -> Array[TextReplace] {
  match self.text_replace {
    Some(a) => a
    None => []
  }
}

///|
pub fn LowerSpec::text_replace_pairs(
  self : LowerSpec,
) -> Array[TextReplacePair] {
  match self.text_replace_pairs {
    Some(a) => a
    None => []
  }
}

///|
pub fn LowerSpec::regex_replace(self : LowerSpec) -> Array[RegexReplace] {
  match self.regex_replace {
    Some(a) => a
    None => []
  }
}

///|
pub fn LowerSpec::collect_separators(self : LowerSpec) -> Map[String, String] {
  match self.collect_separators {
    Some(m) => m
    None => Map([])
  }
}

///|
pub fn LowerSpec::module_aliases(self : LowerSpec) -> Map[String, String] {
  match self.module_aliases {
    Some(m) => m
    None => Map([])
  }
}

///|
pub fn LowerSpec::symbol_aliases(self : LowerSpec) -> Map[String, String] {
  match self.symbol_aliases {
    Some(m) => m
    None => Map([])
  }
}

///|
pub fn LowerSpec::variant_case_style(self : LowerSpec) -> String {
  match self.variant_case_style {
    Some(s) => s
    None => "pascal"
  }
}

///|
/// Optional limits / metadata. `unresolved_marker` defaults to
/// `@@UNRESOLVED@@` when absent.
pub struct TranspileLimits {
  comment : String?
  unresolved_marker : String?
} derive(Debug, FromJson, ToJson)

///|
/// One language's transpile capabilities. A language can be a source-only
/// (only `lift`), target-only (only `lower`), or full (both).
pub struct LanguageSpec {
  language : String
  lift : LiftSpec?
  lower : LowerSpec?
  limits : TranspileLimits?
} derive(Debug, FromJson, ToJson)

///|
pub fn LanguageSpec::language(self : LanguageSpec) -> String {
  self.language
}

///|
pub fn LanguageSpec::lift(self : LanguageSpec) -> LiftSpec? {
  self.lift
}

///|
pub fn LanguageSpec::lower(self : LanguageSpec) -> LowerSpec? {
  self.lower
}

///|
pub fn LanguageSpec::unresolved_marker(self : LanguageSpec) -> String {
  match self.limits {
    Some({ unresolved_marker: Some(s), .. }) => s
    _ => "@@UNRESOLVED@@"
  }
}

///|
/// Load one language spec from `path`.
pub fn load_language_spec(path : String) -> LanguageSpec? {
  let content = @fs.read_file_to_string(path) catch { _ => return None }
  let json : Json = @json.parse(content) catch { _ => return None }
  let spec : LanguageSpec = @json.from_json(json) catch { _ => return None }
  Some(spec)
}

///|
/// Find the spec for `language` by scanning the kgf-transpile directory and
/// matching by the spec's `language` field. The filename is irrelevant —
/// callers must NEVER infer it from the language name.
pub fn find_spec(language : String) -> LanguageSpec? {
  let dir = match @config.find_kgf_transpile_dir() {
    Some(d) => d
    None => return None
  }
  let entries = @fs.read_dir(dir) catch { _ => return None }
  for entry in entries {
    let path = @config.join_path(dir, entry)
    let spec = match load_language_spec(path) {
      Some(s) => s
      None => continue
    }
    if spec.language == language {
      return Some(spec)
    }
  }
  None
}
