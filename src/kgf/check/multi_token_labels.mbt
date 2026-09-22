///|
/// Static detection of `$label` reads that silently truncate a multi-token
/// capture to its last token.
///
/// When a grammar label is bound to a *rule* reference rather than to a single
/// token — `module:RelativeQN`, `doc:DocBlock`, `path:QualifiedName` — the PEG
/// publishes two different things for it (see `FLabel` in
/// `src/kgf/peg/eval_recursive.mbt`):
///
/// - `<label>`      — `META_LAST`, i.e. the value of the **last** token the
///                    capture matched;
/// - `<label>_text` — the **accumulated** text of every token it matched.
///
/// For a capture that can only ever match one token the two agree, so `$label`
/// is correct and idiomatic. For a capture that can match several, `$label`
/// keeps the tail and drops everything in front of it, which is almost never
/// what the spec author meant: a Rust `doc:DocBlock` keeps only the last `///`
/// line, a Python `module:RelativeQN` turns `from .auth` into `auth` and
/// `a.b.c` into `c`, a Haskell import path collapses to its last segment.
///
/// Nothing fails at runtime — the label resolves, the edge is emitted, the
/// attribute is just wrong — so this is reported as a warning pointing at
/// `$label_text`.

///|
/// How many tokens a grammar expression can consume, as far as this check
/// needs to distinguish. Counting exactly is neither possible (a `*` is
/// unbounded) nor useful: the only question is "can this capture end up
/// holding more than one token?".
priv enum TokenSpan {
  /// Matches no tokens at all — a predicate, or a rule that is only made of
  /// predicates. A label bound to this never has a `META_LAST` to publish.
  None
  /// Matches exactly one token on every successful path.
  One
  /// Can match two or more tokens on at least one path.
  Many
} derive(Eq)

///|
/// Combines two spans that run one after the other in a sequence.
fn TokenSpan::then(self : TokenSpan, other : TokenSpan) -> TokenSpan {
  match (self, other) {
    (TokenSpan::Many, _) | (_, TokenSpan::Many) => TokenSpan::Many
    // One token followed by another token is already two.
    (TokenSpan::One, TokenSpan::One) => TokenSpan::Many
    (TokenSpan::None, span) | (span, TokenSpan::None) => span
  }
}

///|
/// Combines two spans that are alternatives of one another. The capture is
/// unsafe as soon as a single alternative can be multi-token, and the
/// single-token verdict only survives if every alternative agrees.
fn TokenSpan::or(self : TokenSpan, other : TokenSpan) -> TokenSpan {
  match (self, other) {
    (TokenSpan::Many, _) | (_, TokenSpan::Many) => TokenSpan::Many
    (TokenSpan::One, _) | (_, TokenSpan::One) => TokenSpan::One
    _ => TokenSpan::None
  }
}

///|
/// Span of a repetition body repeated an unbounded number of times. A body
/// that consumes nothing stays empty however often it repeats; anything that
/// consumes at least one token can repeat into many.
fn TokenSpan::repeated(self : TokenSpan) -> TokenSpan {
  match self {
    TokenSpan::None => TokenSpan::None
    _ => TokenSpan::Many
  }
}

///|
/// Resolves how many tokens `node` can consume, following rule references
/// through `rules`.
///
/// `in_progress` holds the rules currently on the resolution stack. A grammar
/// rule that reaches itself is left-or-right recursive, which means it can
/// expand to arbitrarily many tokens; returning `Many` for the cycle edge is
/// both the safe answer and the correct one.
fn span_of_node(
  node : @kgf_peg.Node,
  rules : Map[String, @kgf_types.RuleDef],
  in_progress : Map[String, Bool],
  memo : Map[String, TokenSpan],
) -> TokenSpan {
  match node {
    @kgf_peg.Empty => TokenSpan::None
    // Lookahead predicates match without consuming input.
    @kgf_peg.And(_) | @kgf_peg.Not(_) => TokenSpan::None
    @kgf_peg.Sym(name) => span_of_symbol(name, rules, in_progress, memo)
    // A label wrapping an expression consumes exactly what the expression does.
    @kgf_peg.Label(_, child) => span_of_node(child, rules, in_progress, memo)
    @kgf_peg.Seq(children) => {
      let mut span = TokenSpan::None
      for child in children {
        span = span.then(span_of_node(child, rules, in_progress, memo))
        // Nothing later in the sequence can bring it back below two.
        if span == TokenSpan::Many {
          return TokenSpan::Many
        }
      }
      span
    }
    @kgf_peg.Choice(children) => {
      let mut span = TokenSpan::None
      for child in children {
        span = span.or(span_of_node(child, rules, in_progress, memo))
        if span == TokenSpan::Many {
          return TokenSpan::Many
        }
      }
      span
    }
    @kgf_peg.Star(child) | @kgf_peg.Plus(child) =>
      span_of_node(child, rules, in_progress, memo).repeated()
    // `e?` either matches `e` or nothing; the non-empty branch is what a
    // label would capture.
    @kgf_peg.Optional(child) => span_of_node(child, rules, in_progress, memo)
  }
}

///|
/// Span of a bare symbol reference: a token kind counts as one token, a rule
/// name expands to the rule's expression.
fn span_of_symbol(
  name : String,
  rules : Map[String, @kgf_types.RuleDef],
  in_progress : Map[String, Bool],
  memo : Map[String, TokenSpan],
) -> TokenSpan {
  match rules.get(name) {
    Some(rule_def) => {
      match memo.get(name) {
        Some(span) => return span
        None => ()
      }
      // Recursive rule: it can expand through itself, so it is unbounded.
      if in_progress.contains(name) {
        return TokenSpan::Many
      }
      in_progress.set(name, true)
      // A malformed expression is already an error from `check_grammar`.
      // Answering `Many` here would stack a second, derived warning on top of
      // it, so claim the quiet single-token answer instead.
      let expr = @kgf_peg.parse_expr(rule_def.get_expr()) catch {
        _ => {
          in_progress.remove(name)
          memo.set(name, TokenSpan::One)
          return TokenSpan::One
        }
      }
      let span = span_of_node(expr, rules, in_progress, memo)
      in_progress.remove(name)
      memo.set(name, span)
      span
    }
    // Not a rule, so it is a token kind: exactly one token. An undefined
    // symbol lands here too, but that is already an error from
    // `check_grammar`, and counting it as one token keeps this check from
    // piling a second, derived warning on top of it.
    None => TokenSpan::One
  }
}

///|
/// Labels of a rule whose capture can span more than one token, mapped to the
/// grammar symbol they are bound to (used to name the culprit in the message).
///
/// Only labels bound directly by this rule's own expression are considered:
/// named labels do not leak out of a referenced sub-rule, so those are the
/// only ones the rule's semantics can read.
fn multi_token_labels_of_rule(
  rule_def : @kgf_types.RuleDef,
  rules : Map[String, @kgf_types.RuleDef],
) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  let node = @kgf_peg.parse_expr(rule_def.get_expr()) catch { _ => return out }
  let memo : Map[String, TokenSpan] = Map([])
  collect_multi_token_labels(node, rules, memo, out)
  out
}

///|
/// Walks an expression and records every label whose captured span is `Many`.
fn collect_multi_token_labels(
  node : @kgf_peg.Node,
  rules : Map[String, @kgf_types.RuleDef],
  memo : Map[String, TokenSpan],
  out : Map[String, String],
) -> Unit {
  match node {
    @kgf_peg.Label(name, child) => {
      let in_progress : Map[String, Bool] = Map([])
      if span_of_node(child, rules, in_progress, memo) == TokenSpan::Many {
        out.set(name, describe_label_target(child))
      }
      // Nested labels inside the capture are bound too and deserve the same
      // treatment (`outer:( a / inner:Multi )`).
      collect_multi_token_labels(child, rules, memo, out)
    }
    @kgf_peg.Seq(children) | @kgf_peg.Choice(children) =>
      for child in children {
        collect_multi_token_labels(child, rules, memo, out)
      }
    @kgf_peg.Star(child)
    | @kgf_peg.Plus(child)
    | @kgf_peg.Optional(child)
    | @kgf_peg.And(child)
    | @kgf_peg.Not(child) => collect_multi_token_labels(child, rules, memo, out)
    @kgf_peg.Empty | @kgf_peg.Sym(_) => ()
  }
}

///|
/// A short description of what a label is bound to, for the warning message.
/// The common case by far is a plain rule reference, which is named directly;
/// anything else is described by its shape.
fn describe_label_target(node : @kgf_peg.Node) -> String {
  match node {
    @kgf_peg.Sym(name) => name
    @kgf_peg.Optional(child) => describe_label_target(child) + "?"
    @kgf_peg.Star(child) => describe_label_target(child) + "*"
    @kgf_peg.Plus(child) => describe_label_target(child) + "+"
    _ => "a multi-token expression"
  }
}

///|
/// The one warning text, shared by the semantics and attrs reporters so the
/// two stay phrased identically. `section` is the spec section the offending
/// read lives in, so a reader can go straight to it.
fn multi_token_message(
  section : String,
  rule_name : String,
  label : String,
  target : String,
  read_as : String,
) -> Diagnostic {
  Diagnostic::new(
    section,
    "warning",
    "In rule '" +
    rule_name +
    "': " +
    read_as +
    " reads label '" +
    label +
    "', bound to " +
    target +
    ", which can match more than one token; it yields only the last token's value — use $" +
    label +
    "_text for the full capture",
  )
}

///|
/// Reports `$label` reads in `=== semantics` where `label` is bound to a
/// multi-token capture.
fn check_semantics_multi_token_labels(
  spec : @kgf_types.KGFSpec,
  diagnostics : Array[Diagnostic],
) -> Unit {
  let semantics = match spec.get_semantics() {
    Some(sem) => sem
    None => return
  }
  let rules = spec.get_rules()
  for entry in semantics {
    let rule_name = entry.0
    let rule_def = match rules.get(rule_name) {
      Some(r) => r
      // Virtual or undefined rules are handled by `check_semantics`.
      None => continue
    }
    let multi = multi_token_labels_of_rule(rule_def, rules)
    if multi.is_empty() {
      continue
    }
    // `let` locals can shadow a label name; once one does, later `$name`
    // reads resolve to the local and are not truncating label reads.
    let reported : Map[String, Bool] = Map([])
    for block in entry.1 {
      let shadowed : Map[String, Bool] = Map([])
      match block.get_when_cond() {
        Some(cond) =>
          report_multi_token_expr(
            cond, rule_name, multi, shadowed, reported, diagnostics,
          )
        None => ()
      }
      report_multi_token_stmts(
        block.get_then_stmts(),
        rule_name,
        multi,
        shadowed,
        reported,
        diagnostics,
      )
      match block.get_else_stmts() {
        Some(stmts) =>
          report_multi_token_stmts(
            stmts, rule_name, multi, shadowed, reported, diagnostics,
          )
        None => ()
      }
    }
  }
}

///|
/// Reports every `$name` in an expression that reads a multi-token label.
fn report_multi_token_expr(
  expr : @kgf_types.SemExpr,
  rule_name : String,
  multi : Map[String, String],
  shadowed : Map[String, Bool],
  reported : Map[String, Bool],
  diagnostics : Array[Diagnostic],
) -> Unit {
  match expr {
    @kgf_types.Var(name) => {
      // `$name_text` is the correct read and must never be flagged; only the
      // bare label name truncates.
      if shadowed.contains(name) || reported.contains(name) {
        return
      }
      match multi.get(name) {
        Some(target) => {
          reported.set(name, true)
          diagnostics.push(
            multi_token_message(
              "semantics",
              rule_name,
              name,
              target,
              "$" + name,
            ),
          )
        }
        None => ()
      }
    }
    @kgf_types.Call(_, args) | @kgf_types.Func(_, args) =>
      for arg in args {
        report_multi_token_expr(
          arg, rule_name, multi, shadowed, reported, diagnostics,
        )
      }
    _ => ()
  }
}

///|
/// Walks statements in order so a `let`/`for` binding shadows the label for
/// everything that follows it, exactly as the evaluator resolves locals.
fn report_multi_token_stmts(
  stmts : Array[@kgf_types.SemStmt],
  rule_name : String,
  multi : Map[String, String],
  shadowed : Map[String, Bool],
  reported : Map[String, Bool],
  diagnostics : Array[Diagnostic],
) -> Unit {
  for stmt in stmts {
    match stmt {
      @kgf_types.Edge(from~, to~, attrs~, ..) => {
        report_multi_token_expr(
          from, rule_name, multi, shadowed, reported, diagnostics,
        )
        report_multi_token_expr(
          to, rule_name, multi, shadowed, reported, diagnostics,
        )
        match attrs {
          Some(a) =>
            report_multi_token_expr(
              a, rule_name, multi, shadowed, reported, diagnostics,
            )
          None => ()
        }
      }
      @kgf_types.Bind(ns~, name~, to~) => {
        report_multi_token_expr(
          ns, rule_name, multi, shadowed, reported, diagnostics,
        )
        report_multi_token_expr(
          name, rule_name, multi, shadowed, reported, diagnostics,
        )
        report_multi_token_expr(
          to, rule_name, multi, shadowed, reported, diagnostics,
        )
      }
      @kgf_types.Note(payload~, ..) =>
        match payload {
          Some(p) =>
            report_multi_token_expr(
              p, rule_name, multi, shadowed, reported, diagnostics,
            )
          None => ()
        }
      @kgf_types.Let(id~, value~) => {
        report_multi_token_expr(
          value, rule_name, multi, shadowed, reported, diagnostics,
        )
        shadowed.set(id, true)
      }
      @kgf_types.For(id~, iter~, body~) => {
        report_multi_token_expr(
          iter, rule_name, multi, shadowed, reported, diagnostics,
        )
        shadowed.set(id, true)
        report_multi_token_stmts(
          body, rule_name, multi, shadowed, reported, diagnostics,
        )
      }
      @kgf_types.Module(id~, file~) => {
        report_multi_token_expr(
          id, rule_name, multi, shadowed, reported, diagnostics,
        )
        match file {
          Some(f) =>
            report_multi_token_expr(
              f, rule_name, multi, shadowed, reported, diagnostics,
            )
          None => ()
        }
      }
      // Frame management reads no labels.
      @kgf_types.ScopePush | @kgf_types.ScopePop => ()
    }
  }
}

///|
/// True when an `=== attrs` parameter reads the label's raw value (and is
/// therefore truncated by a multi-token capture) rather than its `_text`.
///
/// This mirrors `@kgf_semantics.eval_attrs` exactly:
/// - `def doc=X` is the one parameter read as `X_text`, so it is safe;
/// - `def id=X`, `ref name=X`, `call callee=X` and `import`/`reexport`
///   `module=X` all read `labels.get(X)`, the last-token value.
///
/// `is_label_valued_attr_param` (static_refs.mbt) decides *whether* a
/// parameter names a label at all; this decides *how* the value is read.
fn attr_param_reads_raw_label_value(action_kind : String, key : String) -> Bool {
  is_label_valued_attr_param(action_kind, key) &&
  // `doc` is the sole `_text` reader in eval_attr_def.
  !(action_kind == "def" && key == "doc")
}

///|
/// Reports `=== attrs` parameters that read a multi-token label's raw value.
fn check_attrs_multi_token_labels(
  spec : @kgf_types.KGFSpec,
  diagnostics : Array[Diagnostic],
) -> Unit {
  let rules = spec.get_rules()
  for entry in spec.get_attrs() {
    let rule_name = entry.0
    let rule_def = match rules.get(rule_name) {
      Some(r) => r
      None => continue
    }
    let multi = multi_token_labels_of_rule(rule_def, rules)
    if multi.is_empty() {
      continue
    }
    let reported : Map[String, Bool] = Map([])
    for action in entry.1 {
      let kind = action.get_kind()
      for param in action.get_params() {
        let key = param.0
        let label = param.1
        if !attr_param_reads_raw_label_value(kind, key) ||
          reported.contains(label) {
          continue
        }
        match multi.get(label) {
          Some(target) => {
            reported.set(label, true)
            diagnostics.push(
              multi_token_message(
                "attrs",
                rule_name,
                label,
                target,
                kind + " " + key + "=" + label,
              ),
            )
          }
          None => ()
        }
      }
    }
  }
}
