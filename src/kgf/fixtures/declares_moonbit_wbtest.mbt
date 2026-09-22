///|
/// Regression tests for the MoonBit KGF spec (`kgfs/programming/moonbit.kgf`).
///
/// Each test pins down one lexing/parsing defect that made
/// `indexion check --include='*.mbt' src cmd` report thousands of
/// "unrecognized input" errors and abort three parses outright:
///
///   1. multi-line string lines (`#|` raw / `$|` interpolated) were not
///      tokens, so the `#` was rejected and the line body was lexed as code;
///   2. attribute lines (`#deprecated(...)`, `#doc(hidden)`) were not tokens
///      and had no place in the grammar;
///   3. char / byte literals with escapes or non-BMP characters did not match
///      the single-character `Char` token;
///   4. the `Operator` token was missing `%`, `^`, `~`, `|>`, `..`, `..=`,
///      the compound assignments and other members of the operator set;
///   5. a `#|` body containing unbalanced brackets left `Body` unclosed, so
///      the whole remainder of the file stopped parsing.
///
/// Sources that must themselves contain `#|` or `$|` cannot be written in a
/// `#|` raw string (the prefix would be consumed by the outer literal), so
/// those cases build their source from an ordinary escaped `"..."` literal.

///|
/// Helper: the tokens the MoonBit spec produces for `source`, as
/// (kind, text) pairs in lexical order.
fn mbt_tokens_of(
  registry : @registry.KGFRegistry,
  source : String,
) -> Array[(String, String)] {
  let spec = registry.get_spec("moonbit").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let result : Array[(String, String)] = []
  for token in lexer.tokenize(source) {
    result.push((token.kind, token.text))
  }
  result
}

///|
/// Helper: whether `source` lexes with no diagnostics. A diagnostic is exactly
/// the "unrecognized input: X" that `indexion check` reports, so this is the
/// direct assertion for every root cause below.
fn mbt_lexes_cleanly(registry : @registry.KGFRegistry, source : String) -> Bool {
  let spec = registry.get_spec("moonbit").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let (_, diagnostics) = lexer.tokenize_with_diagnostics(source)
  diagnostics.length() == 0
}

///|
/// Helper: the token kinds of `source`, deduplicated into a set-like map.
fn mbt_token_kinds(
  registry : @registry.KGFRegistry,
  source : String,
) -> Map[String, Bool] {
  let kinds : Map[String, Bool] = Map([])
  for pair in mbt_tokens_of(registry, source) {
    kinds.set(pair.0, true)
  }
  kinds
}

///|
/// Helper: the texts lexed as `kind` in `source`, in order.
fn mbt_texts_of_kind(
  registry : @registry.KGFRegistry,
  source : String,
  kind : String,
) -> Array[String] {
  let result : Array[String] = []
  for pair in mbt_tokens_of(registry, source) {
    if pair.0 == kind {
      result.push(pair.1)
    }
  }
  result
}

///|
/// Helper: the `declares` edges of `source` as a name -> lowercased kind map.
fn mbt_declared_names(
  registry : @registry.KGFRegistry,
  source : String,
  path : String,
) -> Map[String, String] {
  let (_, _, names) = count_declares(registry, "moonbit", source, path)
  names
}

///|
/// Helper: the `declares` edges of `source` as (name, doc) pairs, so that a
/// test can assert the doc comment survived the surrounding syntax.
fn mbt_declared_docs(
  registry : @registry.KGFRegistry,
  source : String,
  path : String,
) -> Map[String, String] {
  let docs : Map[String, String] = Map([])
  for edge in declares_of(registry, "moonbit", source, path) {
    docs.set(edge.1, edge.3)
  }
  docs
}

// ─── Root cause 1: multi-line string lines ──────────────────

///|
/// A `#|` line is one `RawStringLine` token covering the whole line, and a
/// `$|` line is one `InterpStringLine` token. Previously the `#` / `$` was
/// rejected as unrecognized input and the rest of the line was lexed as code.
test "moonbit: raw and interpolated string lines are single tokens" {
  // Built from an escaped literal: the source under test contains `#|`/`$|`.
  let source = "pub fn banner(lang : String) -> String {\n" +
    "  let text =\n" +
    "    #| Hello\n" +
    "    $|\\{lang}\n" +
    "    #| Bye\n" +
    "  text\n" +
    "}\n"
  assert_true(mbt_lexes_cleanly(registry_for_moonbit(), source))
  let raw = mbt_texts_of_kind(registry_for_moonbit(), source, "RawStringLine")
  assert_eq(raw.length(), 2)
  assert_eq(raw[0], "#| Hello")
  assert_eq(raw[1], "#| Bye")
  let interp = mbt_texts_of_kind(
    registry_for_moonbit(),
    source,
    "InterpStringLine",
  )
  assert_eq(interp.length(), 1)
  assert_eq(interp[0], "$|\\{lang}")
  // Nothing inside the literal leaked out as code.
  let kinds = mbt_token_kinds(registry_for_moonbit(), source)
  assert_true(!kinds.contains("PIPE"))
}

///|
/// The content of a `#|` line is string data, not MoonBit code: a `pub fn`
/// written inside a multi-line string must not produce a `declares` edge.
/// This is what made `indexion grep "KW_pub KW_fn Ident"` report matches that
/// lived inside test fixtures rather than in real declarations.
test "moonbit: declarations inside a raw string are not declared" {
  let source = "///|\n" +
    "/// Returns an embedded spec.\n" +
    "pub fn embedded_spec() -> String {\n" +
    "  let text =\n" +
    "    #|pub fn looks_like_a_declaration() -> Int {\n" +
    "    #|  42\n" +
    "    #|}\n" +
    "  text\n" +
    "}\n"
  assert_true(mbt_lexes_cleanly(registry_for_moonbit(), source))
  let names = mbt_declared_names(registry_for_moonbit(), source, "embedded.mbt")
  assert_true(names.get("embedded_spec") == Some("function"))
  assert_true(!names.contains("looks_like_a_declaration"))
  assert_eq(names.length(), 1)
}

///|
/// Text that is not MoonBit at all — CJK prose, backticks, `$`, `%`, `^`,
/// backslashes — is legal inside a multi-line string and must lex cleanly.
test "moonbit: arbitrary text inside a raw string lexes cleanly" {
  let source = "pub fn doc_body() -> String {\n" +
    "  let text =\n" +
    "    #|## 見出し\n" +
    "    #|`code` $VAR 100% a^b \\\\ path\\n\n" +
    "    #|<a:theme name=\"x\">'Sheet'!$A$2</a:theme>\n" +
    "  text\n" +
    "}\n"
  assert_true(mbt_lexes_cleanly(registry_for_moonbit(), source))
  let raw = mbt_texts_of_kind(registry_for_moonbit(), source, "RawStringLine")
  assert_eq(raw.length(), 3)
  assert_eq(raw[0], "#|## 見出し")
  let names = mbt_declared_names(registry_for_moonbit(), source, "body.mbt")
  assert_true(names.get("doc_body") == Some("function"))
}

// ─── Root cause 2: attribute lines ──────────────────────────

///|
/// `#deprecated("...")`, `#doc(hidden)` and a bare `#deprecated` are single
/// `Attribute` tokens, and a declaration carrying them is still declared.
test "moonbit: attribute lines are tokens and keep the declaration" {
  let registry = registry_for_moonbit()
  let source =
    #|///|
    #|/// The first function.
    #|pub fn first() -> Int {
    #|  1
    #|}
    #|
    #|///|
    #|/// The second function is deprecated.
    #|#deprecated("Use `first` instead")
    #|#doc(hidden)
    #|pub fn second() -> Int {
    #|  2
    #|}
    #|
    #|///|
    #|/// A deprecated struct.
    #|#deprecated
    #|pub struct Old {
    #|  x : Int
    #|}
  assert_true(mbt_lexes_cleanly(registry, source))
  let attrs = mbt_texts_of_kind(registry, source, "Attribute")
  assert_eq(attrs.length(), 3)
  assert_eq(attrs[0], "#deprecated(\"Use `first` instead\")")
  assert_eq(attrs[1], "#doc(hidden)")
  assert_eq(attrs[2], "#deprecated")
  let names = mbt_declared_names(registry, source, "attrs.mbt")
  assert_true(names.get("first") == Some("function"))
  assert_true(names.get("second") == Some("function"))
  assert_true(names.get("Old") == Some("struct"))
}

///|
/// Attribute lines sit between a doc block and its declaration keyword. The
/// doc must still reach the declaration rather than being absorbed as module
/// documentation by `ModuleDoc`'s `!DeclKeyword` lookahead.
test "moonbit: doc survives attribute lines before the declaration" {
  let registry = registry_for_moonbit()
  let source =
    #|///|
    #|/// Documented despite the attributes.
    #|#deprecated("Use `bar` instead")
    #|#doc(hidden)
    #|pub fn foo() -> Int {
    #|  1
    #|}
  assert_true(mbt_lexes_cleanly(registry, source))
  let docs = mbt_declared_docs(registry, source, "doc_attrs.mbt")
  assert_eq(docs.get("foo"), Some("Documented despite the attributes."))
}

///|
/// A user-defined (namespaced) attribute such as `#custom.attribute(...)` is
/// also one token, per the MoonBit attribute grammar
/// `'#' LIDENT ('.' LIDENT)?`.
test "moonbit: namespaced attribute is a single token" {
  let registry = registry_for_moonbit()
  let source =
    #|///|
    #|#custom.attribute(key="value", flag=true)
    #|pub fn annotated() -> Unit {
    #|  ()
    #|}
  assert_true(mbt_lexes_cleanly(registry, source))
  let attrs = mbt_texts_of_kind(registry, source, "Attribute")
  assert_eq(attrs.length(), 1)
  assert_eq(attrs[0], "#custom.attribute(key=\"value\", flag=true)")
  let names = mbt_declared_names(registry, source, "ns_attr.mbt")
  assert_true(names.get("annotated") == Some("function"))
}

// ─── Root cause 3: char and byte literals ───────────────────

///|
/// Char and byte literals with escapes (`\x00`, `\o102`, `\u0030`,
/// `\u{FFFF}`, `\\`), with a `b` prefix, and with a non-BMP character all
/// lex as one `Char` token. Input is matched in UTF-16 code units, so the
/// emoji is a surrogate pair and needs a two-unit body.
test "moonbit: char and byte literals with escapes and non-ascii" {
  let registry = registry_for_moonbit()
  let source =
    #|///|
    #|pub fn literals() -> Unit {
    #|  let a = '\x00'
    #|  let b = '\u{FFFF}'
    #|  let d = b'\x00'
    #|  let e = b'\o102'
    #|  let f = '\\'
    #|  let g = '\n'
    #|  let h = '中'
    #|  let i = '😀'
    #|  let j = 'A'
    #|  ignore([a, b, f, g, h, i, j])
    #|  ignore([d, e])
    #|}
  assert_true(mbt_lexes_cleanly(registry, source))
  let chars = mbt_texts_of_kind(registry, source, "Char")
  assert_eq(chars.length(), 9)
  assert_eq(chars[0], "'\\x00'")
  assert_eq(chars[1], "'\\u{FFFF}'")
  assert_eq(chars[2], "b'\\x00'")
  assert_eq(chars[3], "b'\\o102'")
  assert_eq(chars[4], "'\\\\'")
  assert_eq(chars[5], "'\\n'")
  assert_eq(chars[6], "'中'")
  assert_eq(chars[7], "'😀'")
  assert_eq(chars[8], "'A'")
  let names = mbt_declared_names(registry, source, "literals.mbt")
  assert_true(names.get("literals") == Some("function"))
}

///|
/// Adjacent char literals must not be merged by the two-code-unit body: the
/// matcher has to back off to a one-unit body when two units do not close the
/// literal. `'a', 'b'` is two `Char` tokens, not one spanning `a', 'b`.
test "moonbit: adjacent char literals stay separate tokens" {
  let registry = registry_for_moonbit()
  let source =
    #|///|
    #|pub fn pair() -> Unit {
    #|  ignore(['a', 'b'])
    #|}
  assert_true(mbt_lexes_cleanly(registry, source))
  let chars = mbt_texts_of_kind(registry, source, "Char")
  assert_eq(chars.length(), 2)
  assert_eq(chars[0], "'a'")
  assert_eq(chars[1], "'b'")
}

///|
/// `b"..."` is a Bytes literal and shares the `String` token shape.
test "moonbit: bytes literal lexes as a string token" {
  let registry = registry_for_moonbit()
  let source =
    #|///|
    #|pub fn bytes_literal() -> Bytes {
    #|  b"\x61\x62"
    #|}
  assert_true(mbt_lexes_cleanly(registry, source))
  let strings = mbt_texts_of_kind(registry, source, "String")
  assert_eq(strings.length(), 1)
  assert_eq(strings[0], "b\"\\x61\\x62\"")
  let names = mbt_declared_names(registry, source, "bytes.mbt")
  assert_true(names.get("bytes_literal") == Some("function"))
}

// ─── Root cause 4: the operator set ─────────────────────────

///|
/// The operator set must cover everything a MoonBit body can contain. `%` and
/// `^` in particular were missing and produced "unrecognized input" for every
/// modulo and xor in the codebase.
test "moonbit: full operator set lexes without unrecognized input" {
  let registry = registry_for_moonbit()
  let source =
    #|///|
    #|pub fn ops(a : Int, b : Int) -> Int {
    #|  let x = a % b
    #|  let y = a ^ b
    #|  let z = (a << 2) >> 1
    #|  let w = (a & b) | (~a)
    #|  let v = if a >= b && a != b || a <= b { 1 } else { 0 }
    #|  let p = a ** 2
    #|  let mut acc = 0
    #|  acc += x
    #|  acc -= y
    #|  acc *= 2
    #|  acc /= 3
    #|  acc %= 5
    #|  acc &= 7
    #|  acc ^= 9
    #|  acc <<= 1
    #|  acc >>= 1
    #|  for i in 0..<b {
    #|    acc = acc + i
    #|  }
    #|  for i in 0..=b {
    #|    acc = acc + i
    #|  }
    #|  acc |> ignore
    #|  x + y + z + w + v + p + acc
    #|}
  // Every code unit is claimed by some token: an unlexed character would show
  // up as a gap, and the declaration below would not be reachable.
  assert_true(mbt_lexes_cleanly(registry, source))
  let names = mbt_declared_names(registry, source, "ops.mbt")
  assert_true(names.get("ops") == Some("function"))
  let kinds = mbt_token_kinds(registry, source)
  assert_true(kinds.contains("Operator"))
}

///|
/// `%` and `^` specifically: the two operators that accounted for the
/// arithmetic half of the "unrecognized input" errors.
test "moonbit: modulo and xor are operator tokens" {
  let registry = registry_for_moonbit()
  let source =
    #|///|
    #|pub fn mix(e : Int, f : Int) -> Int {
    #|  (e & f) ^ ((e ^ 0xFFFFFFFF) & f) + e % 7
    #|}
  assert_true(mbt_lexes_cleanly(registry, source))
  let ops = mbt_texts_of_kind(registry, source, "Operator")
  let mut modulo = 0
  let mut xor = 0
  for op in ops {
    if op == "%" {
      modulo += 1
    }
    if op == "^" {
      xor += 1
    }
  }
  assert_eq(modulo, 1)
  assert_eq(xor, 2)
}

// ─── Root cause 5: raw strings that unbalance brackets ──────

///|
/// A `#|` line whose content contains unbalanced brackets used to leave the
/// enclosing `Body` unclosed, which stopped the parse for the rest of the
/// file. Everything after such a function must still be parsed and declared.
test "moonbit: unbalanced brackets in a raw string do not stop the parse" {
  let source = "///|\n" +
    "pub fn embedded_grammar() -> String {\n" +
    "  let text =\n" +
    "    #|TOKEN LBRACE /\\{/\n" +
    "    #|VarItem -> id:Ident [ COLON Type ] [ EQ Expr ]\n" +
    "    #|TOKEN NumberLit /(?:0|[1-9][0-9]*)/\n" +
    "  text\n" +
    "}\n" +
    "\n" +
    "///|\n" +
    "/// Declared after the embedded grammar.\n" +
    "pub fn after() -> Int {\n" +
    "  1\n" +
    "}\n"
  let registry = registry_for_moonbit()
  assert_true(mbt_lexes_cleanly(registry, source))
  let names = mbt_declared_names(registry, source, "grammar.mbt")
  assert_true(names.get("embedded_grammar") == Some("function"))
  // The parse used to stop inside the first body; `after` proves it does not.
  assert_true(names.get("after") == Some("function"))
  let docs = mbt_declared_docs(registry, source, "grammar.mbt")
  assert_eq(docs.get("after"), Some("Declared after the embedded grammar."))
}

///|
/// Helper: the shared fixture registry, named locally so that the intent of
/// each assertion reads as "the MoonBit spec says ...".
fn registry_for_moonbit() -> @registry.KGFRegistry {
  get_fixture_registry()
}

///|
/// The four-hex-digit `\uXXXX` escape is built from an ordinary string
/// literal: a `#|` line would hand the compiler's own unescaped character to
/// the lexer instead of the escape sequence under test.
test "moonbit: four-digit unicode char escape lexes as one Char" {
  let registry = registry_for_moonbit()
  let source = "///|\npub fn u() -> Unit {\n  let c = '\\u0030'\n  ignore(c)\n}\n"
  assert_true(mbt_lexes_cleanly(registry, source))
  let chars = mbt_texts_of_kind(registry, source, "Char")
  assert_eq(chars, ["'\\u0030'"])
}
