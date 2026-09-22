# indexion kgf

KGF spec management and inspection.

## Usage

```bash
indexion kgf [options] <command>
```

## Global Options

| Option | Description | Default |
|--------|-------------|---------|
| `--spec=NAME` | Specify KGF spec name (auto-detect if omitted) | auto |
| `--kgf-dir=DIR` | KGF specs directory | `kgfs` |

## Subcommands

| Command | Description |
|---------|-------------|
| `list` | List installed KGF specs |
| `update` | Update all specs from GitHub |
| `add` | Download and install a single spec |
| `inspect` | Full inspection (tokens, events, edges) |
| `tokens` | Show tokenization only |
| `events` | Show parse events only |
| `edges` | Show generated edges only |
| `check` | Validate KGF spec structure (see [Validation](#validation-kgf-check)) |
| `classify train` | Train a Naive Bayes section classifier from labeled documents |

## Examples

```bash
# List installed specs
indexion kgf list

# Inspect a file (auto-detect language)
indexion kgf inspect src/config/app.mbt

# Show tokens only
indexion kgf tokens --spec=moonbit src/config/app.mbt

# Show dependency edges
indexion kgf edges src/config/app.mbt

# Train a section classifier from RFC corpus
indexion kgf classify train --spec=rfc-plaintext --min-weight=3.5 /path/to/rfc-corpus/

# Train from ISO document corpus
indexion kgf classify train --spec=technical-document --min-weight=3.5 /path/to/iso-specs/
```

## Validation (`kgf check`)

```bash
# One spec, by registered name or by path
indexion kgf check rust
indexion kgf check kgfs/programming/rust.kgf

# Every spec in the KGF directory, plus the cross-spec source-pattern report
indexion kgf check --all
```

Every run ends with a summary line:

```
Checked 83 spec(s): 0 error(s), 284 warning(s)
```

`--all` takes no positional argument. It validates each registered spec in
name order and then adds the registry-level `[sources]` report, which is the
only diagnostic that needs more than one spec to detect.

### Errors

An error means the spec cannot work as written.

| Section | Diagnostic |
|---------|-----------|
| `lex` | A token has an empty pattern, or a regex that does not compile |
| `grammar` | A rule references a symbol that is neither a token nor a rule |
| `attrs` | An `on Rule:` line names a rule the grammar does not define |
| `semantics` | An `on Rule { }` block names a rule the grammar does not define |
| `semantics` | A `$name(...)` call is not a known built-in |

### Warnings

A warning means the spec loads and runs, but the engine quietly does
something other than what the spec appears to say. These are the failure
modes that produce wrong graph data without producing any error.

**Unbound label reference** (`semantics`, `attrs`) — the block reads `$doc`,
or an attrs parameter names `doc`, but the rule's own grammar expression never
binds that label. Labels bound inside a *referenced* rule do not leak out to
the caller, which is the usual cause. `eval_var` answers `Json::null()` for an
unknown name and `obj(...)` drops nulls, so the attribute silently disappears
from every edge the block emits.

**Built-in shadowing** (`semantics`) — `let file = ...` declares a local whose
name is a built-in variable. The evaluator resolves built-ins first, so the
local can never be read back; rename it.

**Unreachable token kind** (`grammar`) — a non-`skip` token that no grammar
rule references. The lexer still emits it, but nothing can consume it, so the
start rule stops in front of the first occurrence and the remainder of the
file never reaches events, semantics or edges.

**Multi-token capture read as `$label`** (`semantics`) — the label is bound to
a grammar expression that can match more than one token, and the spec reads it
as `$label`. The PEG publishes two different values for such a capture:

| Read | Value |
|------|-------|
| `$label` | `_last` — the **last** token the capture matched |
| `$label_text` | the **accumulated** text of every token it matched |

so `$label` keeps the tail and drops everything before it. A capture is
treated as multi-token when its expression contains a sequence of two or more
elements, a `+` or `*` repetition, or a reference to another rule that is
itself multi-token (resolved recursively, with cycles counted as unbounded). A
rule whose every alternative is a single token reference — `Name -> Ident /
TypeIdent` — is single-token and is never reported. Observed effects: a Rust
`doc:DocBlock` keeps only the last `///` line; a Python `module:RelativeQN`
turns `from .auth` into `auth` and `from a.b.c` into `c`.

In `=== attrs` the same truncation applies to every parameter the evaluator
reads as a raw label value — `def id=`, `ref name=`, `call callee=`,
`import`/`reexport` `module=`. `def doc=` is the one parameter read as
`<label>_text`, so binding it to a multi-token capture is correct and is not
reported.

The fix in both cases is `$label_text`.

**Contested source pattern** (`sources`, `--all` only) — several specs declare
the same entry in `resolver.sources`. Only one can own it: `register_spec`
lets the last general-purpose spec to register win, and files matching the
pattern are never analysed with the specs that lost. The report names the
winner and every shadowed spec; it does not change which spec wins.
`kgf list` marks the same patterns inline, with `(*)` on the winner's row and
`(shadowed by <winner>)` on each loser's.
