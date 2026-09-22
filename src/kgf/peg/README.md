# peg

## Event delivery guarantee

Parsing a file produces a stream of **rule-match events** — one per rule that
matched — and each event drives the spec's `semantics` / `attrs` actions
(`bind`, `scope push` / `scope pop`, symbol registration, edge emission).
The evaluators guarantee:

> An event is delivered **if and only if** the rule instance that produced it
> is part of the final successful derivation, **in post-order** (children
> before their parent), **exactly once** per instance.

A PEG backtracks, so a rule can match inside an alternative that the enclosing
sequence later rejects. Such a match is *not* in the parse, and reporting it
would run a `bind` or push a scope for a derivation the parser abandoned —
which is how scope balance used to drift. Events are therefore not emitted as
rules succeed: each result carries a handle into an append-only event arena,
a rejected alternative drops its children's handle, and the surviving handle
is walked once when parsing ends. Because the handle is an immutable index,
merging is O(1) (no quadratic concatenation), a memoized success replays its
subtree's events when reused, and a memo entry that is only probed emits
nothing.

Consequences worth knowing:

- **Lookahead predicates** (`&X`, `!X`) contribute no events: they consume no
  input and their sub-derivation is not part of the parse tree.
- **Alias rules** (`Outer -> Inner`) emit like any other rule — after `Inner`,
  before `Outer`'s parent — so `on Outer { ... }` fires.
- **A rule reference is not a rule instance.** Referring to a rule from
  several places does not multiply its events; each instance is reported once.
- **Partial parses** still deliver the events of the prefix that was consumed.
  `run_parse_with_diagnostics` shares the same delivery point, so a diagnostic
  run sees exactly what a plain run sees.

`src/kgf/peg/transactional_events_wbtest.mbt` pins all of the above, and pins
the recursive and iterative evaluators to each other.

## API

- **`compute_brace_pairs`** (Function) — Computes bracket pairs from tokens in O(n).
- **`CompiledNode`** (Enum) — CompiledNode is an ID-based representation for evaluation hot paths.
- **`Labels`** (Enum) — Lazy labels: defer Map creation until actually needed.
- **`FastCompiledNode`** (Enum) — FastCompiledNode separates tokens and rules for O(1) matching.
- **`get_close`** (Function) — Gets the matching close bracket position for an open bracket.
- **`parse_choice`** (Function) — Parses a choice expression (alternatives separated by / or |).
- **`merge_into_map`** (Function) — Merges labels into a target Map (in place).
- **`parse_primary`** (Function) — Parses a primary expression (identifier, label, parenthesized group, bracketed optional, or predicate).
- **`parse_expr_with_warnings`** (Function) — Parses a PEG expression string into a Node AST, returning deprecation warnings.
- **`WorkItem`** (Enum) — Work item for the evaluation stack.
- **`BracePairs`** (Struct) — BracePairs maps opening bracket positions to closing bracket positions.
- **`MemoState`** (Enum) — Memo entry states for memoization.
- **`compile_node`** (Function) — Compiles an AST node into ID-based node table for faster evaluation.
- **`is_stop_token`** (Function) — Returns true if current token is a stop token (RP, RB, BAR, SLASH).
- **`is_and`** (Function) — Returns true if this node is an And predicate (positive lookahead).

And 195 more symbols.
