// Tests for `extends:` diagnostics and for checking the RESOLVED spec.

///|
/// Build the language-keyed source set `check_extends` resolves against.
fn extends_sources(texts : Array[String]) -> Map[String, @parser.KGFSpecSource] {
  let by_language : Map[String, @parser.KGFSpecSource] = Map([])
  for text in texts {
    let source = @parser.parse_kgf_source(text)
    by_language.set(source.get_language(), source)
  }
  by_language
}

///|
/// Reports whether any diagnostic's message contains `needle`.
fn has_message(diagnostics : Array[Diagnostic], needle : String) -> Bool {
  for diagnostic in diagnostics {
    if diagnostic.get_message().contains(needle) {
      return true
    }
  }
  false
}

///|
let check_base_text : String =
  #|kgf 0.6
  #|language: c-base
  #|sources: .cbase
  #|
  #|=== lex
  #|SKIP /\s+/
  #|TOKEN WORD /[a-z]+/
  #|
  #|=== grammar
  #|Doc -> Line*
  #|Line -> word:WORD

///|
test "check_extends: a resolvable base produces no diagnostics" {
  let derived_text =
    #|kgf 0.6
    #|language: c-derived
    #|sources: .cderived
    #|extends: c-base
  let by_language = extends_sources([check_base_text, derived_text])
  let diagnostics = check_extends(
    by_language.get("c-derived").unwrap(),
    by_language,
  )
  assert_eq(diagnostics.length(), 0)
}

///|
test "check_extends: unknown base is an error naming both specs" {
  let text =
    #|kgf 0.6
    #|language: c-orphan
    #|extends: c-missing
  let by_language = extends_sources([text])
  let diagnostics = check_extends(
    by_language.get("c-orphan").unwrap(),
    by_language,
  )
  assert_eq(diagnostics.length(), 1)
  assert_eq(diagnostics[0].get_severity(), "error")
  assert_eq(diagnostics[0].get_section(), "extends")
  assert_true(has_message(diagnostics, "c-orphan"))
  assert_true(has_message(diagnostics, "c-missing"))
}

///|
test "check_extends: a cycle is an error listing the chain" {
  let a_text =
    #|kgf 0.6
    #|language: c-a
    #|extends: c-b
  let b_text =
    #|kgf 0.6
    #|language: c-b
    #|extends: c-a
  let by_language = extends_sources([a_text, b_text])
  let diagnostics = check_extends(by_language.get("c-a").unwrap(), by_language)
  assert_eq(diagnostics.length(), 1)
  assert_eq(diagnostics[0].get_severity(), "error")
  assert_true(has_message(diagnostics, "c-a -> c-b -> c-a"))
}

///|
test "check_extends: an empty `extends:` value is an error" {
  let text =
    #|kgf 0.6
    #|language: c-empty
    #|extends:
  let by_language = extends_sources([text])
  let diagnostics = check_extends(
    by_language.get("c-empty").unwrap(),
    by_language,
  )
  assert_eq(diagnostics.length(), 1)
  assert_true(has_message(diagnostics, "no value"))
}

///|
test "check_extends_all: reports every spec's problem once" {
  let orphan_text =
    #|kgf 0.6
    #|language: c-orphan
    #|extends: c-missing
  let ok_text =
    #|kgf 0.6
    #|language: c-derived
    #|extends: c-base
  let by_language = extends_sources([check_base_text, orphan_text, ok_text])
  let diagnostics = check_extends_all(by_language)
  assert_eq(diagnostics.length(), 1)
  assert_true(has_message(diagnostics, "c-missing"))
}

///|
test "check: the resolved spec is validated, not the derived text alone" {
  // The derived spec adds semantics that bind against the INHERITED grammar.
  // Checking the derived text on its own would report "semantic block for
  // undefined rule 'Line'"; checking the resolved spec must not.
  let derived_text =
    #|kgf 0.6
    #|language: c-derived
    #|sources: .cderived
    #|extends: c-base
    #|
    #|=== semantics
    #|on Line {
    #|  edge declares from $file to $word
    #|}
  let by_language = extends_sources([check_base_text, derived_text])
  let derived = by_language.get("c-derived").unwrap()
  // Unresolved: the semantics reference a rule the derived text never defines.
  let unresolved = check(derived.to_spec())
  assert_true(has_message(unresolved, "undefined rule 'Line'"))
  // Resolved: the inherited grammar supplies `Line`, so it checks clean.
  let (resolved, _) = @registry.resolve_spec_source(derived, by_language)
  assert_eq(check(resolved.to_spec()).length(), 0)
}

///|
test "check: a derived semantics label unbound in the inherited grammar is reported" {
  // The mirror case: with the inherited grammar in place, a label the base
  // does not capture is a real error the resolved check must surface.
  let derived_text =
    #|kgf 0.6
    #|language: c-derived
    #|sources: .cderived
    #|extends: c-base
    #|
    #|=== semantics
    #|on Line {
    #|  edge declares from $file to $nosuchlabel()
    #|}
  let by_language = extends_sources([check_base_text, derived_text])
  let derived = by_language.get("c-derived").unwrap()
  let (resolved, _) = @registry.resolve_spec_source(derived, by_language)
  let diagnostics = check(resolved.to_spec())
  assert_true(has_message(diagnostics, "nosuchlabel"))
}

///|
test "check_extends_all: every shipped spec resolves" {
  let dir = @kgf_fixtures.get_kgfs_dir()
  let is_dir = @fs.is_dir(dir) catch { _ => false }
  if !is_dir {
    return
  }
  assert_eq(check_extends_all(load_spec_sources(dir)).length(), 0)
}
