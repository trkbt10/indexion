///|
/// Proxy function detection tests using fixtures.

///|
test "proxy: detects simple package delegation" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()
  let source = @fs.read_file_to_string(
    fixtures + "/proxy/moonbit/simple_proxy.mbt",
  ) catch {
    _ => ""
  }
  if source.length() > 0 {
    let proxies = @features.detect_proxy_functions_from_file(
      source,
      "simple_proxy.mbt",
      Some(registry),
    )
    // Should detect 4 proxy functions
    assert_true(proxies.length() == 4)
    // First: round_ties_even_f32
    assert_eq(proxies[0].name, "round_ties_even_f32")
    assert_eq(proxies[0].delegate_target, "@math.round_ties_even_f32")
    assert_true(proxies[0].all_forwarded)
    assert_eq(proxies[0].delegate_args.length(), 1)
  }
}

///|
test "proxy: detects Type::method delegation" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()
  let source = @fs.read_file_to_string(
    fixtures + "/proxy/moonbit/simple_proxy.mbt",
  ) catch {
    _ => ""
  }
  if source.length() > 0 {
    let proxies = @features.detect_proxy_functions_from_file(
      source,
      "simple_proxy.mbt",
      Some(registry),
    )
    // Second function: Type::f32bits_hex
    assert_eq(proxies[1].name, "f32bits_hex")
    assert_eq(proxies[1].delegate_target, "@math.Type::f32bits_hex")
    assert_true(proxies[1].all_forwarded)
  }
}

///|
test "proxy: detects zero-arg proxy" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()
  let source = @fs.read_file_to_string(
    fixtures + "/proxy/moonbit/simple_proxy.mbt",
  ) catch {
    _ => ""
  }
  if source.length() > 0 {
    let proxies = @features.detect_proxy_functions_from_file(
      source,
      "simple_proxy.mbt",
      Some(registry),
    )
    // Third function: zero_arg_proxy
    assert_eq(proxies[2].name, "zero_arg_proxy")
    assert_eq(proxies[2].delegate_target, "@util.get_default")
    assert_true(proxies[2].all_forwarded)
    assert_eq(proxies[2].params.length(), 0)
    assert_eq(proxies[2].delegate_args.length(), 0)
  }
}

///|
test "proxy: detects multi-param forwarding" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()
  let source = @fs.read_file_to_string(
    fixtures + "/proxy/moonbit/simple_proxy.mbt",
  ) catch {
    _ => ""
  }
  if source.length() > 0 {
    let proxies = @features.detect_proxy_functions_from_file(
      source,
      "simple_proxy.mbt",
      Some(registry),
    )
    // Fourth function: multi_param
    assert_eq(proxies[3].name, "multi_param")
    assert_eq(proxies[3].delegate_target, "@checker.validate")
    assert_true(proxies[3].all_forwarded)
    assert_eq(proxies[3].params.length(), 3)
  }
}

///|
test "proxy: rejects non-proxy functions" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()
  let source = @fs.read_file_to_string(
    fixtures + "/proxy/moonbit/not_proxy.mbt",
  ) catch {
    _ => ""
  }
  if source.length() > 0 {
    let proxies = @features.detect_proxy_functions_from_file(
      source,
      "not_proxy.mbt",
      Some(registry),
    )
    // Should detect 0 proxy functions — all have additional logic
    assert_eq(proxies.length(), 0)
  }
}

///|
test "proxy: def_start_line includes doc comment" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()
  let source = @fs.read_file_to_string(
    fixtures + "/proxy/moonbit/simple_proxy.mbt",
  ) catch {
    _ => ""
  }
  if source.length() > 0 {
    let proxies = @features.detect_proxy_functions_from_file(
      source,
      "simple_proxy.mbt",
      Some(registry),
    )
    // First function starts at line 2 (fn), but ///| is at line 1
    assert_eq(proxies[0].def_start_line, 1)
    assert_eq(proxies[0].line, 2)
    // Definition ends at line 4 (closing brace)
    assert_eq(proxies[0].def_end_line, 4)
  }
}

///|
test "proxy: find_call_sites detects calls in caller file" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()
  let source = @fs.read_file_to_string(fixtures + "/proxy/moonbit/caller.mbt") catch {
    _ => ""
  }
  if source.length() > 0 {
    let spec = registry.get_spec("moonbit").unwrap()
    let lexer_inst = @lexer.Lexer::new(spec.get_tokens())
    let tokens = lexer_inst.tokenize(source)
    let edits = @features.find_call_sites(
      "round_ties_even_f32", "@math.round_ties_even_f32", tokens, "caller.mbt",
    )
    // Should find 1 call site (line 3)
    assert_eq(edits.length(), 1)
    assert_eq(edits[0].old_text, "round_ties_even_f32")
    assert_eq(edits[0].new_text, "@math.round_ties_even_f32")
    assert_eq(edits[0].line, 3)
  }
}

///|
test "proxy: apply_edits replaces call target" {
  let content = "fn foo() { bar(x) }"
  let edit = @features.UnwrapEdit::new("test.mbt", 11, 14, "bar", "@pkg.baz", 1)
  let result = @features.apply_edits(content, [edit])
  assert_eq(result, "fn foo() { @pkg.baz(x) }")
}

///|
test "proxy: delete_lines removes function definition" {
  let content = "line1\n///|\nfn foo() {\n  bar()\n}\nline6\n"
  let result = @features.delete_lines(content, 2, 5)
  assert_eq(result, "line1\nline6\n")
}
