///|
/// Tests for the PEG evaluator's event-delivery guarantee.
///
/// An event is delivered if and only if the rule instance that produced it
/// belongs to the final successful derivation — in post-order (children
/// before parents), exactly once per instance. A rule that matched inside an
/// alternative the parser later rejected must leave no trace, because every
/// event drives a semantics/attrs action (`bind`, `scope push`, symbol
/// registration, edge emission) that must not run for a derivation that is
/// not in the parse.
///
/// Both evaluators are held to the same guarantee, and to each other.

///|
/// Builds a PEG from spec source, tokenizes `source`, and returns the event
/// names each evaluator delivers.
fn te_event_names(
  spec_src : String,
  source : String,
  start_rule : String,
  use_iterative : Bool,
) -> Array[String] {
  let spec = @parser.parse_kgf(spec_src).unwrap()
  let peg = build_peg(spec) catch { _ => panic() }
  let lexer = @lexer.Lexer::for_spec(spec)
  let tokens = lexer.tokenize(source)
  // Emit every rule: `collect_active_rules` keeps only rules carrying
  // semantics/attrs blocks, and these specs are pure grammar.
  let active_rules : @hashset.HashSet[String] = HashSet([])
  for name, _ in spec.get_rules() {
    active_rules.add(name)
  }
  // Reach the two evaluators by their own entry points: the dispatcher in
  // `eval.mbt` picks one by token count, which would leave the other
  // untested.
  let result = if use_iterative {
    run_parse_filtered_iter(peg, spec, start_rule, tokens, active_rules)
  } else {
    run_parse_filtered_rec(peg, spec, start_rule, tokens, active_rules)
  }
  let names : Array[String] = []
  match result {
    Some(r) =>
      for event in r.events {
        names.push(event.0)
      }
    None => ()
  }
  names
}

///|
/// Asserts that both evaluators deliver exactly `expected`, which also
/// pins the two implementations to each other.
fn te_assert_events(
  spec_src : String,
  source : String,
  start_rule : String,
  expected : Array[String],
) -> Unit raise {
  let rec_names = te_event_names(spec_src, source, start_rule, false)
  let iter_names = te_event_names(spec_src, source, start_rule, true)
  assert_eq(rec_names, expected)
  assert_eq(iter_names, expected)
}

///|
/// Counts how many times `name` appears in `names`.
fn te_count(names : Array[String], name : String) -> Int {
  let mut n = 0
  for candidate in names {
    if candidate == name {
      n = n + 1
    }
  }
  n
}

///|
/// The reported reproduction: `Pair` is tried first and fails after `Head`
/// already matched, then `Single` succeeds and re-matches `Head` from the
/// memo. `Head` belongs to the parse once, so it must be reported once.
fn te_backtrack_kgf() -> String {
  let text =
    #|language: te_backtrack
    #|
    #|=== lex
    #|SKIP /[ \t\n]+/
    #|TOKEN A /a/
    #|TOKEN B /b/
    #|TOKEN C /c/
    #|
    #|=== grammar
    #|Doc -> Item*
    #|Item -> Pair / Single
    #|Pair -> Head B
    #|Single -> Head C
    #|Head -> x:A
    #|
  text
}

///|
test "transactional events: backtracked alternative emits nothing" {
  // Before the fix this was `Head, Head, Single, Item, Doc` — the first
  // `Head` coming from the abandoned `Pair` attempt.
  te_assert_events(te_backtrack_kgf(), "a c", "Doc", [
    "Head", "Single", "Item", "Doc",
  ])
}

///|
test "transactional events: Head fires exactly once despite memo reuse" {
  // `Head` is probed from `Pair` (which fails) and then reused from the memo
  // by `Single` (which succeeds). A memoized success must replay its events
  // when reused, and emit nothing while merely being probed — so exactly one.
  let names = te_event_names(te_backtrack_kgf(), "a c", "Doc", true)
  assert_eq(te_count(names, "Head"), 1)
  let rec_names = te_event_names(te_backtrack_kgf(), "a c", "Doc", false)
  assert_eq(te_count(rec_names, "Head"), 1)
}

///|
test "transactional events: winning alternative still reports its subtree" {
  // The mirror case: `Pair` succeeds, so `Head` is reported under it.
  te_assert_events(te_backtrack_kgf(), "a b", "Doc", [
    "Head", "Pair", "Item", "Doc",
  ])
}

///|
/// Three nested levels of backtracking: the first alternative of every level
/// matches a prefix and then fails, so each level must discard the events of
/// its abandoned attempt.
fn te_nested_kgf() -> String {
  let text =
    #|language: te_nested
    #|
    #|=== lex
    #|SKIP /[ \t\n]+/
    #|TOKEN A /a/
    #|TOKEN B /b/
    #|TOKEN C /c/
    #|TOKEN D /d/
    #|
    #|=== grammar
    #|Top -> L1
    #|L1 -> L2 D / L2
    #|L2 -> L3 D / L3 C
    #|L3 -> Leaf D / Leaf B
    #|Leaf -> x:A
    #|
  text
}

///|
test "transactional events: three levels of nested backtracking" {
  // Input `a b c`: at each of the three levels the first alternative gets
  // as far as matching its sub-rule and then fails on the `D` that is not
  // there, so each level backtracks and takes its second alternative. Only
  // the surviving derivation may be reported, each rule once — the three
  // abandoned attempts must contribute nothing.
  let names = te_event_names(te_nested_kgf(), "a b c", "Top", true)
  assert_eq(te_count(names, "Leaf"), 1)
  assert_eq(te_count(names, "L3"), 1)
  assert_eq(te_count(names, "L2"), 1)
  assert_eq(te_count(names, "L1"), 1)
  assert_eq(te_count(names, "Top"), 1)
  // Post-order: every child precedes its parent.
  te_assert_events(te_nested_kgf(), "a b c", "Top", [
    "Leaf", "L3", "L2", "L1", "Top",
  ])
}

///|
/// A `*` loop whose element can partially match before failing: after two
/// good items the third attempt consumes `Head` and then stops, and that
/// abandoned iteration must contribute nothing.
fn te_star_kgf() -> String {
  let text =
    #|language: te_star
    #|
    #|=== lex
    #|SKIP /[ \t\n]+/
    #|TOKEN A /a/
    #|TOKEN B /b/
    #|TOKEN Z /z/
    #|
    #|=== grammar
    #|Doc -> Item* Tail
    #|Item -> Head B
    #|Head -> x:A
    #|Tail -> Z
    #|
  text
}

///|
test "transactional events: star loop that partially matches then stops" {
  // `a b a b a z`: the third iteration matches `Head` (the `a`) and then
  // fails on `B`, so the loop stops. That `Head` is not in the parse — the
  // `a` is left for... nothing, so the whole parse fails.
  let names = te_event_names(te_star_kgf(), "a b a b z", "Doc", true)
  assert_eq(names, ["Head", "Item", "Head", "Item", "Tail", "Doc"])
  // Two complete iterations, no phantom third `Head`.
  assert_eq(te_count(names, "Head"), 2)
  assert_eq(te_count(names, "Item"), 2)
  te_assert_events(te_star_kgf(), "a b a b z", "Doc", [
    "Head", "Item", "Head", "Item", "Tail", "Doc",
  ])
}

///|
test "transactional events: empty star loop reports only the parent" {
  te_assert_events(te_star_kgf(), "z", "Doc", ["Tail", "Doc"])
}

///|
/// An alias rule: `Outer -> Inner`, whose body is a single rule reference.
fn te_alias_kgf() -> String {
  let text =
    #|language: te_alias
    #|
    #|=== lex
    #|SKIP /[ \t\n]+/
    #|TOKEN A /a/
    #|
    #|=== grammar
    #|Doc -> Outer
    #|Outer -> Inner
    #|Inner -> x:A
    #|
  text
}

///|
test "transactional events: alias rules emit once" {
  // `Outer`'s body is just `Inner`. It used to be silently suppressed, so
  // `on Outer { ... }` never fired. It emits like any other rule now: after
  // `Inner`, before `Outer`'s parent.
  let names = te_event_names(te_alias_kgf(), "a", "Doc", true)
  assert_eq(te_count(names, "Outer"), 1)
  assert_eq(te_count(names, "Inner"), 1)
  te_assert_events(te_alias_kgf(), "a", "Doc", ["Inner", "Outer", "Doc"])
}

///|
/// A rule referenced from several places, to pin that a rule *reference* is
/// pure indirection and only the rule instance itself is reported.
fn te_shared_kgf() -> String {
  let text =
    #|language: te_shared
    #|
    #|=== lex
    #|SKIP /[ \t\n]+/
    #|TOKEN A /a/
    #|TOKEN B /b/
    #|
    #|=== grammar
    #|Doc -> Pair
    #|Pair -> Atom Atom
    #|Atom -> x:A / y:B
    #|
  text
}

///|
test "transactional events: each rule instance is reported exactly once" {
  // Two `Atom` instances, one per position — not two per hop through the
  // rule reference.
  let names = te_event_names(te_shared_kgf(), "a b", "Doc", true)
  assert_eq(te_count(names, "Atom"), 2)
  te_assert_events(te_shared_kgf(), "a b", "Doc", [
    "Atom", "Atom", "Pair", "Doc",
  ])
}

///|
test "transactional events: lookahead predicates contribute no events" {
  let spec_src =
    #|language: te_pred
    #|
    #|=== lex
    #|SKIP /[ \t\n]+/
    #|TOKEN A /a/
    #|TOKEN B /b/
    #|
    #|=== grammar
    #|Doc -> &Probe Real
    #|Probe -> x:A
    #|Real -> y:A z:B
    #|
  // `Probe` matches inside a lookahead, which consumes nothing and is not
  // part of the parse tree, so it must not be reported.
  let names = te_event_names(spec_src, "a b", "Doc", true)
  assert_eq(te_count(names, "Probe"), 0)
  te_assert_events(spec_src, "a b", "Doc", ["Real", "Doc"])
}

///|
test "transactional events: recursive and iterative evaluators agree" {
  // Parity across every shape exercised above, on both matching and
  // non-matching inputs.
  let cases : Array[(String, String, String)] = [
    (te_backtrack_kgf(), "a c", "Doc"),
    (te_backtrack_kgf(), "a b", "Doc"),
    (te_backtrack_kgf(), "a b a c a b", "Doc"),
    (te_nested_kgf(), "a b c", "Top"),
    (te_star_kgf(), "a b a b z", "Doc"),
    (te_star_kgf(), "z", "Doc"),
    (te_alias_kgf(), "a", "Doc"),
    (te_shared_kgf(), "a b", "Doc"),
    (te_shared_kgf(), "b a", "Doc"),
  ]
  for c in cases {
    let (spec_src, source, start_rule) = c
    let rec_names = te_event_names(spec_src, source, start_rule, false)
    let iter_names = te_event_names(spec_src, source, start_rule, true)
    assert_eq(rec_names, iter_names)
  }
}

///|
test "transactional events: repeated backtracking does not accumulate" {
  // Every `Item` takes the failing `Pair` branch first. Before the fix the
  // phantom `Head`s grew with the input; now the count is exactly one per
  // item, so the event stream stays proportional to the parse.
  let names = te_event_names(te_backtrack_kgf(), "a c a c a c", "Doc", true)
  assert_eq(te_count(names, "Head"), 3)
  assert_eq(te_count(names, "Single"), 3)
  assert_eq(te_count(names, "Pair"), 0)
  assert_eq(te_count(names, "Item"), 3)
  assert_eq(te_count(names, "Doc"), 1)
}

///|
test "transactional events: diagnostics run delivers the same events" {
  // `run_parse_with_diagnostics` shares the evaluator's delivery point, so a
  // diagnostic run must see exactly what a plain run sees.
  let spec = @parser.parse_kgf(te_backtrack_kgf()).unwrap()
  let peg = build_peg(spec) catch { _ => panic() }
  let lexer = @lexer.Lexer::for_spec(spec)
  let tokens = lexer.tokenize("a c")
  let (result, diagnostic) = run_parse_with_diagnostics(
    peg, spec, "Doc", tokens,
  )
  let names : Array[String] = []
  match result {
    Some(r) =>
      for event in r.events {
        names.push(event.0)
      }
    None => fail("expected the parse to succeed")
  }
  assert_eq(names, ["Head", "Single", "Item", "Doc"])
  assert_true(diagnostic.is_fully_consumed())
}

///|
test "transactional events: partial parse still delivers the consumed prefix" {
  // `Doc -> Item*` stops at the first unparsable token. The events of the
  // prefix it did consume are still delivered; the trailing junk is not.
  let spec_src =
    #|language: te_partial
    #|
    #|=== lex
    #|SKIP /[ \t\n]+/
    #|TOKEN A /a/
    #|TOKEN B /b/
    #|TOKEN Q /q/
    #|
    #|=== grammar
    #|Doc -> Item*
    #|Item -> Head B
    #|Head -> x:A
    #|
  let spec = @parser.parse_kgf(spec_src).unwrap()
  let peg = build_peg(spec) catch { _ => panic() }
  let lexer = @lexer.Lexer::for_spec(spec)
  let tokens = lexer.tokenize("a b q")
  let (result, diagnostic) = run_parse_with_diagnostics(
    peg, spec, "Doc", tokens,
  )
  // The `q` is never consumed, so the parse is not fully consumed...
  assert_false(diagnostic.is_fully_consumed())
  // ...but the one complete `Item` before it is reported.
  match result {
    Some(r) => {
      let names : Array[String] = []
      for event in r.events {
        names.push(event.0)
      }
      assert_eq(names, ["Head", "Item", "Doc"])
    }
    None => fail("expected a partial parse to still produce a result")
  }
}
