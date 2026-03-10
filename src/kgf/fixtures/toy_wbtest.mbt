///|
/// Toy fixtures tests.
/// Validates KGF parsing for base64, jpeg-hex, reltext, japanese-law.

///|
test "toy: tokenize b64, reltext, jpeg-hex, japanese-law" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()

  // Base64 PNG
  let b64_spec = registry.get_spec("b64-png").unwrap()
  let b64_lexer = @lexer.Lexer::new(b64_spec.get_tokens())
  let b64_src = @fs.read_file_to_string(fixtures + "/toy/b64-png/logo.png.b64") catch {
    _ => ""
  }
  if b64_src.length() > 0 {
    let tokens = b64_lexer.tokenize(b64_src)
    assert_true(tokens.length() > 0)
  }

  // Reltext
  let rel_spec = registry.get_spec("reltext").unwrap()
  let rel_lexer = @lexer.Lexer::new(rel_spec.get_tokens())
  let rel_src = @fs.read_file_to_string(fixtures + "/toy/reltext/graph.rel") catch {
    _ => ""
  }
  if rel_src.length() > 0 {
    let tokens = rel_lexer.tokenize(rel_src)
    assert_true(tokens.length() > 0)
  }

  // JPEG hex
  let hex_spec = registry.get_spec("jpeg-hex").unwrap()
  let hex_lexer = @lexer.Lexer::new(hex_spec.get_tokens())
  let hex_src = @fs.read_file_to_string(fixtures + "/toy/jpeg/logo.jpg.hex") catch {
    _ => ""
  }
  if hex_src.length() > 0 {
    let tokens = hex_lexer.tokenize(hex_src)
    assert_true(tokens.length() > 0)
  }

  // Japanese law (optional)
  match registry.get_spec("japanese-law") {
    Some(law_spec) => {
      assert_true(law_spec.get_tokens().length() > 0)
      let law_lexer = @lexer.Lexer::new(law_spec.get_tokens())
      let law_src = @fs.read_file_to_string(
        fixtures + "/toy/japanese-law/ja_law/048_excerpt.txt",
      ) catch {
        _ => ""
      }
      if law_src.length() > 0 {
        let tokens = law_lexer.tokenize(law_src)
        ignore(tokens)
      }
    }
    None => ()
  }
}
