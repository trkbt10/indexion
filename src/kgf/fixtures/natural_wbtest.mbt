///|
/// Natural language fixtures tests.
/// Validates KGF parsing for Japanese, English, Chinese, Korean.

///|
test "natural: tokenize japanese, english, korean, chinese" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
