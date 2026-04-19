///|
/// KGF spec validation — checks a parsed KGFSpec for structural errors.
///
/// Detects issues that would otherwise be silently swallowed at runtime:
/// - Invalid regex patterns in lex section
/// - Undefined symbol references in grammar rules
/// - Semantic blocks referencing undefined grammar rules
/// - Undefined built-in functions in semantic expressions
/// - Feature values referencing undefined token kinds
/// - Classify section structural problems

///|
/// A single diagnostic produced by validation.
pub struct Diagnostic {
  section : String
  severity : String // "error" | "warning"
  message : String
}

///|
pub fn Diagnostic::new(
  section : String,
  severity : String,
  message : String,
) -> Diagnostic {
  { section, severity, message }
}

///|
pub fn Diagnostic::get_section(self : Diagnostic) -> String {
  self.section
}

///|
pub fn Diagnostic::get_severity(self : Diagnostic) -> String {
  self.severity
}

///|
pub fn Diagnostic::get_message(self : Diagnostic) -> String {
  self.message
}

///|
/// Validate a KGFSpec and return all diagnostics.
pub fn check(spec : @kgf_types.KGFSpec) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  let token_names = check_lex(spec, diagnostics)
  let rule_names = check_grammar(spec, token_names, diagnostics)
  let all_symbols = merge_symbol_sets(token_names, rule_names)
  check_attrs(spec, rule_names, diagnostics)
  check_semantics(spec, rule_names, all_symbols, diagnostics)
  check_features(spec, token_names, diagnostics)
  check_classify(spec, diagnostics)
  diagnostics
}

///|
/// Check lex section: validate regex patterns.
/// Returns the set of defined token names.
fn check_lex(
  spec : @kgf_types.KGFSpec,
  diagnostics : Array[Diagnostic],
) -> Map[String, Bool] {
  let token_names : Map[String, Bool] = {}
  for token_def in spec.get_tokens() {
    let name = token_def.get_name()
    if name.length() > 0 {
      token_names.set(name, true)
    }
    let pattern = token_def.get_pattern()
    if pattern.length() == 0 {
      diagnostics.push(
        Diagnostic::new(
          "lex",
          "error",
          "Token '" + name + "' has empty pattern",
        ),
      )
      continue
    }
    // Try to compile the regex
    let flags = token_def.get_flags().unwrap_or("")
    let case_insensitive = flags.contains("i")
    match @regexp.compile_pattern(pattern, case_insensitive~) {
      Some(_) => ()
      None =>
        diagnostics.push(
          Diagnostic::new(
            "lex",
            "error",
            "Token '" + name + "' has invalid regex: /" + pattern + "/",
          ),
        )
    }
  }
  // NL is implicitly available even if not defined
  token_names.set("NL", true)
  token_names
}

///|
/// Check grammar section: validate that all referenced symbols exist.
/// Returns the set of defined rule names.
fn check_grammar(
  spec : @kgf_types.KGFSpec,
  token_names : Map[String, Bool],
  diagnostics : Array[Diagnostic],
) -> Map[String, Bool] {
  let rules = spec.get_rules()
  let rule_names : Map[String, Bool] = {}
  for entry in rules {
    rule_names.set(entry.0, true)
  }
  // Check each rule's expression for undefined symbol references
  for entry in rules {
    let rule_name = entry.0
    let rule_def = entry.1
    let expr = rule_def.get_expr()
    let referenced = extract_symbols_from_expr(expr)
    for sym in referenced {
      if !token_names.contains(sym) && !rule_names.contains(sym) {
        diagnostics.push(
          Diagnostic::new(
            "grammar",
            "error",
            "Rule '" + rule_name + "' references undefined symbol '" + sym + "'",
          ),
        )
      }
    }
  }
  rule_names
}

///|
/// Check attrs section: validate that referenced rule names exist.
fn check_attrs(
  spec : @kgf_types.KGFSpec,
  rule_names : Map[String, Bool],
  diagnostics : Array[Diagnostic],
) -> Unit {
  let attrs = spec.get_attrs()
  for entry in attrs {
    let attr_rule = entry.0
    if !rule_names.contains(attr_rule) {
      diagnostics.push(
        Diagnostic::new(
          "attrs",
          "error",
          "Attribute defined for undefined rule '" + attr_rule + "'",
        ),
      )
    }
  }
}

///|
/// Check semantics section: validate rule references and function calls.
fn check_semantics(
  spec : @kgf_types.KGFSpec,
  rule_names : Map[String, Bool],
  all_symbols : Map[String, Bool],
  diagnostics : Array[Diagnostic],
) -> Unit {
  let semantics = match spec.get_semantics() {
    Some(sem) => sem
    None => return
  }
  for entry in semantics {
    let sem_rule = entry.0
    // DocumentSection is a virtual rule created by the section extraction
    // pipeline, not defined in grammar — always valid.
    if sem_rule != "DocumentSection" && !rule_names.contains(sem_rule) {
      diagnostics.push(
        Diagnostic::new(
          "semantics",
          "error",
          "Semantic block defined for undefined rule '" + sem_rule + "'",
        ),
      )
    }
    let blocks = entry.1
    for block in blocks {
      // Check when condition
      match block.get_when_cond() {
        Some(expr) => check_sem_expr(expr, sem_rule, all_symbols, diagnostics)
        None => ()
      }
      // Check then statements
      check_sem_stmts(
        block.get_then_stmts(),
        sem_rule,
        all_symbols,
        diagnostics,
      )
      // Check else statements
      match block.get_else_stmts() {
        Some(stmts) =>
          check_sem_stmts(stmts, sem_rule, all_symbols, diagnostics)
        None => ()
      }
    }
  }
}

///|
/// Check feature values that reference token kinds.
fn check_features(
  spec : @kgf_types.KGFSpec,
  token_names : Map[String, Bool],
  diagnostics : Array[Diagnostic],
) -> Unit {
  let token_referencing_features = @kgf_types.token_referencing_feature_names()
  for feature_name in token_referencing_features {
    match spec.get_feature(feature_name) {
      Some(values) =>
        for value in values {
          if !token_names.contains(value) {
            diagnostics.push(
              Diagnostic::new(
                "features",
                "warning",
                "Feature '" +
                feature_name +
                "' references undefined token kind '" +
                value +
                "'",
              ),
            )
          }
        }
      None => ()
    }
  }
}

///|
/// Check classify section for structural validity.
fn check_classify(
  spec : @kgf_types.KGFSpec,
  diagnostics : Array[Diagnostic],
) -> Unit {
  let model = match spec.get_classify() {
    Some(m) => m
    None => return
  }
  if model.is_empty() && model.get_metadata().is_empty() {
    diagnostics.push(
      Diagnostic::new(
        "classify", "warning", "Classify section is present but empty",
      ),
    )
    return
  }
  let class_names = model.get_class_names()
  for name in class_names {
    match model.get_class(name) {
      Some(cls) =>
        if cls.get_vocab().is_empty() {
          diagnostics.push(
            Diagnostic::new(
              "classify",
              "warning",
              "Class '" + name + "' has no vocabulary terms",
            ),
          )
        }
      None => ()
    }
  }
}

// ── Helpers ──────────────────────────────────────

///|
/// Extract symbol names referenced in a PEG expression string.
/// Symbols are uppercase-starting identifiers (tokens) or any identifier
/// that isn't a PEG operator.
fn extract_symbols_from_expr(expr : String) -> Array[String] {
  let symbols : Array[String] = []
  let seen : Map[String, Bool] = {}
  let buf = StringBuilder::new()
  let chars = expr.to_array()
  for c in chars {
    if @charclass.is_ident_char(c) {
      buf.write_char(c)
    } else {
      let word = buf.to_string()
      if word.length() > 0 && is_symbol_candidate(word) && !seen.contains(word) {
        symbols.push(word)
        seen.set(word, true)
      }
      buf.reset()
    }
  }
  let word = buf.to_string()
  if word.length() > 0 && is_symbol_candidate(word) && !seen.contains(word) {
    symbols.push(word)
  }
  symbols
}

///|
/// Returns true if a word looks like a grammar symbol reference
/// (not a PEG operator keyword or label).
fn is_symbol_candidate(word : String) -> Bool {
  let first = word.to_array()[0]
  // Must start with uppercase letter (rule/token convention)
  first >= 'A' && first <= 'Z'
}

///|
fn merge_symbol_sets(
  a : Map[String, Bool],
  b : Map[String, Bool],
) -> Map[String, Bool] {
  let merged : Map[String, Bool] = {}
  for entry in a {
    merged.set(entry.0, true)
  }
  for entry in b {
    merged.set(entry.0, true)
  }
  merged
}

///|
/// Returns true if `name` is a known function in the KGF semantic DSL.
/// Delegates to the SoT in the semantics package (eval_expr.mbt).
fn is_known_builtin(name : String) -> Bool {
  @kgf_semantics.is_known_call(name) || @kgf_semantics.is_known_func(name)
}

///|
/// Check a semantic expression for undefined function calls.
fn check_sem_expr(
  expr : @kgf_types.SemExpr,
  context_rule : String,
  all_symbols : Map[String, Bool],
  diagnostics : Array[Diagnostic],
) -> Unit {
  match expr {
    @kgf_types.Call(name, args) => {
      if !is_known_builtin(name) && !@kgf_semantics.is_known_builtin_var(name) {
        diagnostics.push(
          Diagnostic::new(
            "semantics",
            "error",
            "In rule '" +
            context_rule +
            "': unknown built-in function '" +
            name +
            "()'",
          ),
        )
      }
      for arg in args {
        check_sem_expr(arg, context_rule, all_symbols, diagnostics)
      }
    }
    @kgf_types.Func(name, args) => {
      if !is_known_builtin(name) {
        diagnostics.push(
          Diagnostic::new(
            "semantics",
            "warning",
            "In rule '" + context_rule + "': unknown function '" + name + "()'",
          ),
        )
      }
      for arg in args {
        check_sem_expr(arg, context_rule, all_symbols, diagnostics)
      }
    }
    _ => ()
  }
}

///|
/// Check a list of semantic statements.
fn check_sem_stmts(
  stmts : Array[@kgf_types.SemStmt],
  context_rule : String,
  all_symbols : Map[String, Bool],
  diagnostics : Array[Diagnostic],
) -> Unit {
  for stmt in stmts {
    match stmt {
      @kgf_types.Edge(from~, to~, attrs~, ..) => {
        check_sem_expr(from, context_rule, all_symbols, diagnostics)
        check_sem_expr(to, context_rule, all_symbols, diagnostics)
        match attrs {
          Some(a) => check_sem_expr(a, context_rule, all_symbols, diagnostics)
          None => ()
        }
      }
      @kgf_types.Bind(ns~, name~, to~) => {
        check_sem_expr(ns, context_rule, all_symbols, diagnostics)
        check_sem_expr(name, context_rule, all_symbols, diagnostics)
        check_sem_expr(to, context_rule, all_symbols, diagnostics)
      }
      @kgf_types.Note(payload~, ..) =>
        match payload {
          Some(p) => check_sem_expr(p, context_rule, all_symbols, diagnostics)
          None => ()
        }
      @kgf_types.Let(value~, ..) =>
        check_sem_expr(value, context_rule, all_symbols, diagnostics)
      @kgf_types.For(body~, iter~, ..) => {
        check_sem_expr(iter, context_rule, all_symbols, diagnostics)
        check_sem_stmts(body, context_rule, all_symbols, diagnostics)
      }
      @kgf_types.Module(id~, file~) => {
        check_sem_expr(id, context_rule, all_symbols, diagnostics)
        match file {
          Some(f) => check_sem_expr(f, context_rule, all_symbols, diagnostics)
          None => ()
        }
      }
    }
  }
}
