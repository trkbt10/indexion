///|
/// Toy fixtures tests.
/// Validates KGF parsing for base64, jpeg-hex, reltext, japanese-law.

///|
test "toy: tokenize b64, reltext, jpeg-hex, japanese-law" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()

  // Base64 PNG
  let b64_spec = registry.get_spec("b64-png").unwrap()
  let b64_lexer = @lexer.Lexer::for_spec(b64_spec)
  let b64_src = @fs.read_file_to_string(fixtures + "/toy/b64-png/logo.png.b64") catch {
    _ => ""
  }
  if b64_src.length() > 0 {
    let tokens = b64_lexer.tokenize(b64_src)
    assert_true(tokens.length() > 0)
  }

  // Reltext
  let rel_spec = registry.get_spec("reltext").unwrap()
  let rel_lexer = @lexer.Lexer::for_spec(rel_spec)
  let rel_src = @fs.read_file_to_string(fixtures + "/toy/reltext/graph.rel") catch {
    _ => ""
  }
  if rel_src.length() > 0 {
    let tokens = rel_lexer.tokenize(rel_src)
    assert_true(tokens.length() > 0)
  }

  // JPEG hex
  let hex_spec = registry.get_spec("jpeg-hex").unwrap()
  let hex_lexer = @lexer.Lexer::for_spec(hex_spec)
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
      let law_lexer = @lexer.Lexer::for_spec(law_spec)
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

///|
/// Toy specs claim no extension, and are reached only by name.
///
/// They used to. Six specs claimed `.b64`, two claimed `.hex`, eight claimed
/// `.txt` — so the registry assigned each pattern to whichever of them
/// happened to register last, and every matching file was decoded with that
/// one spec. `fixtures/toy/png/logo.png.hex` was read by `jpeg-hex` and
/// yielded nothing; the PNG decoder that would have read it correctly never
/// saw the file. Nothing in the output said so: a wrong decoder produces an
/// empty result, not an error.
///
/// Marking them `detection_scope: overlay` silences the conflict report but
/// does not settle the choice — an overlay that is the sole remaining
/// claimant of a pattern is still assigned it. Only dropping `sources:`
/// makes auto-detection refuse the file and say so, which is the honest
/// answer for a format that the extension alone cannot identify.
test "toy: specs claim no extension and are selected by name" {
  let registry = get_fixture_registry()
  let fixtures = get_fixtures_dir()
  for
    name in [
      "base64", "base64-utf8", "b64-png", "b64-jpeg", "png-b64hex", "jpeg-b64hex",
      "png-hex", "jpeg-hex", "reltext", "japanese-law",
    ] {
    let spec = registry.get_spec(name).unwrap()
    assert_eq(spec.get_resolver().get_sources().length(), 0)
    assert_eq(spec.get_feature("detection_scope"), Some(["overlay"]))
  }

  // The right decoder, named explicitly, reads the file the wrong one
  // used to swallow: this is the concrete loss the shared claim caused.
  let png_hex = @fs.read_file_to_string(fixtures + "/toy/png/logo.png.hex") catch {
    _ => ""
  }
  assert_true(png_hex.length() > 0)
  let png_result = run_pipeline_with_registry(
    registry, "png-hex", png_hex, "fixtures/toy/png/logo.png.hex",
  )
  assert_true(png_result.edges.length() > 0)
  let jpeg_result = run_pipeline_with_registry(
    registry, "jpeg-hex", png_hex, "fixtures/toy/png/logo.png.hex",
  )
  assert_eq(jpeg_result.edges.length(), 0)
}
