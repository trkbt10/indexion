///|
/// Static cross-section validations for a KGF spec.
///
/// Two classes of spec bug are invisible at runtime because the engine
/// degrades silently instead of failing:
///
/// - **unbound label reference** — a `=== semantics` block or an `=== attrs`
///   line names a label (`$doc`, `doc=doc`, `def id`) that the rule's grammar
///   expression never binds. `eval_var` returns `Json::null()` for an unknown
///   name and `obj(...)` drops null values, so every edge produced by that
///   block quietly carries an empty attribute.
/// - **unreachable token kind** — a non-SKIP TOKEN/KEYWORD defined in
///   `=== lex` that no grammar rule ever references. The lexer still emits it,
///   but no rule can consume it, so the start rule stops in front of it and
///   the remainder of the file is silently dropped from events, semantics and
///   edges.
///
/// Both are reported as warnings: a spec can be intentionally partial while it
/// is being developed, and neither condition prevents the engine from running.

///|
/// Label names the evaluator always provides, independent of the grammar.
/// These are the reserved meta keys the PEG writes into every label map.
fn is_reserved_meta_label(name : String) -> Bool {
  name == @kgf_types.META_TEXT ||
  name == @kgf_types.META_LAST ||
  name == @kgf_types.META_LAST_POS ||
  name == @kgf_types.META_LAST_LEN ||
  name == @kgf_types.META_START_TOK ||
  name == @kgf_types.META_END_TOK ||
  name == "_children"
}

///|
/// Suffixes the PEG derives from a bound label `foo`: `foo_text`, `foo_pos`,
/// `foo_len` (published by `FLabel`) and `foo_children` (read by `children()`).
/// Returns the base label name when `name` is such a derived form.
fn strip_derived_label_suffix(name : String) -> String? {
  for
    suffix in [
      @kgf_types.META_TEXT_SUFFIX,
      @kgf_types.META_POS_SUFFIX,
      @kgf_types.META_LEN_SUFFIX,
      "_children",
    ] {
    if name.length() > suffix.length() && name.has_suffix(suffix) {
      return Some(name[:name.length() - suffix.length()].to_owned())
    }
  }
  None
}

///|
/// Collect every label bound anywhere inside a parsed PEG expression,
/// including labels nested in groups, repetitions and alternatives
/// (`decorators:( DecoratorLine / prop:PropertyDecoratorLine )*` binds both
/// `decorators` and `prop`).
fn collect_labels_from_node(
  node : @kgf_peg.Node,
  out : Map[String, Bool],
) -> Unit {
  match node {
    @kgf_peg.Label(name, child) => {
      out.set(name, true)
      collect_labels_from_node(child, out)
    }
    @kgf_peg.Seq(children) | @kgf_peg.Choice(children) =>
      for child in children {
        collect_labels_from_node(child, out)
      }
    @kgf_peg.Star(child)
    | @kgf_peg.Plus(child)
    | @kgf_peg.Optional(child)
    | @kgf_peg.And(child)
    | @kgf_peg.Not(child) => collect_labels_from_node(child, out)
    @kgf_peg.Empty | @kgf_peg.Sym(_) => ()
  }
}

///|
/// Labels bound by a rule's grammar expression. Labels bound inside a
/// referenced sub-rule do not leak to the caller (the PEG strips named labels
/// when a rule reference returns), so only this rule's own expression counts.
fn labels_bound_by_rule(rule_def : @kgf_types.RuleDef) -> Map[String, Bool] {
  let labels : Map[String, Bool] = Map([])
  let node = @kgf_peg.parse_expr(rule_def.get_expr()) catch {
    // A malformed expression is already reported by the grammar check; there
    // is nothing meaningful to validate references against.
    _ => return labels
  }
  collect_labels_from_node(node, labels)
  labels
}

///|
/// True when `name` resolves to something at evaluation time for a rule that
/// binds `labels` and has `locals` in scope at that point.
fn is_resolvable_var(
  name : String,
  labels : Map[String, Bool],
  locals : Map[String, Bool],
) -> Bool {
  if name.length() == 0 {
    return true
  }
  if labels.contains(name) || locals.contains(name) {
    return true
  }
  if @kgf_semantics.is_known_builtin_var(name) || is_reserved_meta_label(name) {
    return true
  }
  match strip_derived_label_suffix(name) {
    Some(base) => labels.contains(base) || locals.contains(base)
    None => false
  }
}

///|
/// Walk a semantic expression, reporting every `$name` that nothing binds.
/// `Call` names are built-ins (`$resolve(...)`, `$scope(...)`), not variables,
/// and are validated separately by `check_sem_expr`.
fn check_expr_var_refs(
  expr : @kgf_types.SemExpr,
  rule_name : String,
  labels : Map[String, Bool],
  locals : Map[String, Bool],
  reported : Map[String, Bool],
  diagnostics : Array[Diagnostic],
) -> Unit {
  match expr {
    @kgf_types.Var(name) =>
      if !is_resolvable_var(name, labels, locals) && !reported.contains(name) {
        reported.set(name, true)
        diagnostics.push(
          Diagnostic::new(
            "semantics",
            "warning",
            "In rule '" +
            rule_name +
            "': '$" +
            name +
            "' is not bound by the rule's grammar expression",
          ),
        )
      }
    @kgf_types.Call(_, args) | @kgf_types.Func(_, args) =>
      for arg in args {
        check_expr_var_refs(
          arg, rule_name, labels, locals, reported, diagnostics,
        )
      }
    _ => ()
  }
}

///|
/// Walk semantic statements in order so a `let` local is only visible to the
/// statements that follow it. `locals` is mutated as the walk proceeds.
fn check_stmt_var_refs(
  stmts : Array[@kgf_types.SemStmt],
  rule_name : String,
  labels : Map[String, Bool],
  locals : Map[String, Bool],
  reported : Map[String, Bool],
  diagnostics : Array[Diagnostic],
) -> Unit {
  for stmt in stmts {
    match stmt {
      @kgf_types.Edge(from~, to~, attrs~, ..) => {
        check_expr_var_refs(
          from, rule_name, labels, locals, reported, diagnostics,
        )
        check_expr_var_refs(
          to, rule_name, labels, locals, reported, diagnostics,
        )
        match attrs {
          Some(a) =>
            check_expr_var_refs(
              a, rule_name, labels, locals, reported, diagnostics,
            )
          None => ()
        }
      }
      @kgf_types.Bind(ns~, name~, to~) => {
        check_expr_var_refs(
          ns, rule_name, labels, locals, reported, diagnostics,
        )
        check_expr_var_refs(
          name, rule_name, labels, locals, reported, diagnostics,
        )
        check_expr_var_refs(
          to, rule_name, labels, locals, reported, diagnostics,
        )
      }
      @kgf_types.Note(payload~, ..) =>
        match payload {
          Some(p) =>
            check_expr_var_refs(
              p, rule_name, labels, locals, reported, diagnostics,
            )
          None => ()
        }
      @kgf_types.Let(id~, value~) => {
        check_expr_var_refs(
          value, rule_name, labels, locals, reported, diagnostics,
        )
        // The evaluator resolves the built-in variables before locals, so a
        // local with one of their names can never be read back: `$root`
        // stays the analysis root no matter what `let root = ...` computed.
        if @kgf_semantics.is_known_builtin_var(id) {
          diagnostics.push(
            Diagnostic::new(
              "semantics",
              "warning",
              "In rule '" +
              rule_name +
              "': `let " +
              id +
              "` shadows the built-in variable $" +
              id +
              ", which always wins; rename the local",
            ),
          )
        }
        locals.set(id, true)
      }
      @kgf_types.For(id~, iter~, body~) => {
        check_expr_var_refs(
          iter, rule_name, labels, locals, reported, diagnostics,
        )
        // The loop variable is in scope for the body (and, like `let`, stays
        // visible afterwards because the evaluator keeps one flat local map).
        locals.set(id, true)
        check_stmt_var_refs(
          body, rule_name, labels, locals, reported, diagnostics,
        )
      }
      @kgf_types.Module(id~, file~) => {
        check_expr_var_refs(
          id, rule_name, labels, locals, reported, diagnostics,
        )
        match file {
          Some(f) =>
            check_expr_var_refs(
              f, rule_name, labels, locals, reported, diagnostics,
            )
          None => ()
        }
      }
    }
  }
}

///|
/// Report `$name` references in `=== semantics` blocks that the rule's own
/// grammar expression never binds.
fn check_semantics_label_refs(
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
    // DocumentSection is virtual (produced by the section extraction
    // pipeline, not by the grammar), so it has no expression to check.
    let rule_def = match rules.get(rule_name) {
      Some(r) => r
      // Missing rules are already reported as errors by check_semantics.
      None => continue
    }
    let labels = labels_bound_by_rule(rule_def)
    // One warning per (rule, name): the same unbound label typically appears
    // several times in one block, and repeating it adds nothing.
    let reported : Map[String, Bool] = Map([])
    for block in entry.1 {
      // Each block gets a fresh local scope: `let` bindings do not carry
      // across `on Rule { ... }` blocks.
      let locals : Map[String, Bool] = Map([])
      match block.get_when_cond() {
        Some(cond) =>
          check_expr_var_refs(
            cond, rule_name, labels, locals, reported, diagnostics,
          )
        None => ()
      }
      check_stmt_var_refs(
        block.get_then_stmts(),
        rule_name,
        labels,
        locals,
        reported,
        diagnostics,
      )
      match block.get_else_stmts() {
        Some(stmts) =>
          check_stmt_var_refs(
            stmts, rule_name, labels, locals, reported, diagnostics,
          )
        None => ()
      }
    }
  }
}

///|
/// Attr action parameters whose value names a grammar label rather than a
/// literal, keyed by action kind. This mirrors `@kgf_semantics.eval_attrs`
/// exactly: only the parameters it looks up in the event's label map are
/// checked, and only for the action kinds it implements.
///
/// Action kinds the evaluator does not implement fall through to a no-op
/// there, so nothing in them is resolved at runtime and nothing in them can
/// be an unbound reference. They are deliberately absent here.
fn is_label_valued_attr_param(action_kind : String, key : String) -> Bool {
  match action_kind {
    // eval_attr_def: `id` names the label holding the symbol name, `doc`
    // names the label whose `<label>_text` carries the doc comment.
    // `kind` and `ns` are literals.
    "def" => key == "id" || key == "doc"
    // eval_attr_ref: `name` names the label; `ns` is a literal.
    "ref" => key == "name"
    // eval_attr_call: `callee` names the label.
    "call" => key == "callee"
    // eval_attr_import / eval_attr_reexport: `module` names the label.
    "import" | "reexport" => key == "module"
    // `argref` and `scope` read no labels; every other kind is a no-op.
    _ => false
  }
}

///|
/// Report `=== attrs` parameters that name a label the rule never binds.
fn check_attrs_label_refs(
  spec : @kgf_types.KGFSpec,
  diagnostics : Array[Diagnostic],
) -> Unit {
  let rules = spec.get_rules()
  for entry in spec.get_attrs() {
    let rule_name = entry.0
    let rule_def = match rules.get(rule_name) {
      Some(r) => r
      // Missing rules are already reported as errors by check_attrs.
      None => continue
    }
    let labels = labels_bound_by_rule(rule_def)
    let no_locals : Map[String, Bool] = Map([])
    for action in entry.1 {
      for param in action.get_params() {
        let key = param.0
        let label_name = param.1
        if !is_label_valued_attr_param(action.get_kind(), key) {
          continue
        }
        // `doc=foo` is read as `foo_text`, so the base label is what matters.
        if !is_resolvable_var(label_name, labels, no_locals) {
          diagnostics.push(
            Diagnostic::new(
              "attrs",
              "warning",
              "In rule '" +
              rule_name +
              "': " +
              action.get_kind() +
              " " +
              key +
              "=" +
              label_name +
              " names a label the rule's grammar expression never binds",
            ),
          )
        }
      }
    }
  }
}

///|
/// Report non-SKIP token kinds that no grammar rule references.
///
/// Such a token is still produced by the lexer, but nothing can consume it, so
/// the start rule stops in front of the first occurrence and the rest of the
/// file never reaches events, semantics or edges.
fn check_unreachable_tokens(
  spec : @kgf_types.KGFSpec,
  diagnostics : Array[Diagnostic],
) -> Unit {
  let rules = spec.get_rules()
  // A spec without a grammar section is lex-only by design; nothing to check.
  if rules.is_empty() {
    return
  }
  // Token kinds are not required to start with an uppercase letter (a spec
  // may name a token after the data it matches, e.g. a `tEXt` chunk), so a
  // reference is any identifier word of the rule expression that names a
  // defined token — not only the uppercase-first candidates the grammar
  // symbol check uses.
  let referenced : Map[String, Bool] = Map([])
  for entry in rules {
    for word in identifier_words(entry.1.get_expr()) {
      referenced.set(word, true)
    }
  }
  let reported : Map[String, Bool] = Map([])
  for token_def in spec.get_tokens() {
    let name = token_def.get_name()
    if name.length() == 0 || token_def.is_skip() || reported.contains(name) {
      continue
    }
    if !referenced.contains(name) {
      reported.set(name, true)
      diagnostics.push(
        Diagnostic::new(
          "grammar",
          "warning",
          "Token kind '" +
          name +
          "' is defined in lex but no grammar rule consumes it; a file containing it stops the parse early",
        ),
      )
    }
  }
}
