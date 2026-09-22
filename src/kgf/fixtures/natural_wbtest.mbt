///|
/// Natural language fixtures tests.
/// Validates KGF parsing for Japanese, English, Chinese, Korean.

///|
test "natural: tokenize japanese, english, korean, chinese" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  // Japanese
  let ja_spec = registry.get_spec("japanese").unwrap()
  let ja_lexer = @lexer.Lexer::new(ja_spec.get_tokens())
  let ja_src = @fs.read_file_to_string(
    fixtures + "/natural/japanese/simple.txt",
  ) catch {
    _ => ""
  }
  if ja_src.length() > 0 {
    let tokens = ja_lexer.tokenize(ja_src)
    assert_true(tokens.length() > 0)
    assert_true(
      tokens
      .iter()
      .any(fn(t) {
        t.kind == "Kanji" || t.kind == "Hiragana" || t.kind == "Katakana"
      }),
    )
  }

  // English
  let en_spec = registry.get_spec("english").unwrap()
  let en_lexer = @lexer.Lexer::new(en_spec.get_tokens())
  let en_src = @fs.read_file_to_string(fixtures + "/natural/english/sample.txt") catch {
    _ => ""
  }
  if en_src.length() > 0 {
    let tokens = en_lexer.tokenize(en_src)
    assert_true(tokens.length() > 0)
  }

  // Korean
  let ko_spec = registry.get_spec("korean").unwrap()
  let ko_lexer = @lexer.Lexer::new(ko_spec.get_tokens())
  let ko_src = @fs.read_file_to_string(fixtures + "/natural/korean/sample.txt") catch {
    _ => ""
  }
  if ko_src.length() > 0 {
    let tokens = ko_lexer.tokenize(ko_src)
    assert_true(tokens.length() > 0)
  }

  // Chinese
  let zh_spec = registry.get_spec("chinese").unwrap()
  let zh_lexer = @lexer.Lexer::new(zh_spec.get_tokens())
  let zh_src = @fs.read_file_to_string(fixtures + "/natural/chinese/sample.txt") catch {
    _ => ""
  }
  if zh_src.length() > 0 {
    let tokens = zh_lexer.tokenize(zh_src)
    assert_true(tokens.length() > 0)
  }
}

///|
/// The Japanese grammar required a word before a particle and allowed no
/// particle inside quoted speech, so a line that opens with a particle
/// (`でも、…`) or a bracket stopped the parse and every word after it was
/// dropped. `CjkNumber` was lexed but no rule consumed it at all.
test "natural: japanese parses whole texts including particles and brackets" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()
  for name in ["simple.txt", "quotes.txt", "tech.txt"] {
    let path = fixtures + "/natural/japanese/" + name
    let source = @fs.read_file_to_string(path) catch { _ => "" }
    assert_true(source.length() > 0)
    let result = run_pipeline_with_registry(
      registry, "japanese", source, "text.txt",
    )
    assert_true(result.parse_ok)
    assert_eq(result.tokens_consumed, result.tokens_total)
    assert_eq(result.lex_errors, 0)
  }
}

///|
/// A CJK numeral is a number written in kanji. The token existed but no
/// grammar rule consumed it, so any text containing 一/十/百 stopped there.
test "natural: japanese reads cjk numerals as numbers" {
  let registry = get_fixture_registry()
  let spec = registry.get_spec("japanese").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let source = "彼は三十分待った。でも、誰も来なかった。"
  let tokens = lexer.tokenize(source)
  assert_true(tokens.iter().any(fn(t) { t.kind == "CjkNumber" }))
  let result = run_pipeline_with_registry(
    registry, "japanese", source, "text.txt",
  )
  assert_true(result.parse_complete())
  assert_eq(result.lex_errors, 0)
}

///|
/// Each natural-language spec must consume any of the text fixtures, not
/// only the ones written in its own language: the specs are used as overlays
/// on mixed-language documents.
test "natural: every language spec consumes every text fixture" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()
  let paths = [
    "/natural/japanese/simple.txt", "/natural/english/sample.txt", "/natural/korean/sample.txt",
    "/natural/chinese/sample.txt",
  ]
  for spec_name in ["japanese", "english", "korean", "chinese"] {
    for rel in paths {
      let source = @fs.read_file_to_string(fixtures + rel) catch { _ => "" }
      assert_true(source.length() > 0)
      let result = run_pipeline_with_registry(
        registry, spec_name, source, "text.txt",
      )
      assert_true(result.parse_ok)
      assert_eq(result.tokens_consumed, result.tokens_total)
    }
  }
}
