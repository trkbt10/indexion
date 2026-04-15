///|
/// Protobuf similarity tests.
/// Validates that structurally similar .proto files are detected as similar
/// by the TF-IDF comparison pipeline, and that dissimilar ones are not.

///|
test "similar-code: protobuf pair detected as similar" {
  let fixtures = get_fixtures_dir()
  let a_path = fixtures + "/similar-code/a.proto"
  let b_path = fixtures + "/similar-code/b.proto"
  let a_source = @fs.read_file_to_string(a_path) catch { _ => "" }
  let b_source = @fs.read_file_to_string(b_path) catch { _ => "" }
  if a_source.length() == 0 || b_source.length() == 0 {
    return
  }
  let files = [
    @batch.FileEntry::new("a.proto", a_source),
    @batch.FileEntry::new("b.proto", b_source),
  ]
  let result = @batch.compare_tfidf(files, 0.5)
  assert_eq(result.file_count, 2)
  assert_eq(result.pairs_compared, 1)
  // Structurally similar proto files (same schema pattern, renamed identifiers)
  // should be detected as similar with a reasonable threshold.
  assert_true(result.matches.length() >= 1)
  let m = result.matches[0]
  assert_true(m.similarity > 0.5)
}

///|
test "similar-code: protobuf vs typescript not similar" {
  let fixtures = get_fixtures_dir()
  let proto_path = fixtures + "/similar-code/a.proto"
  let ts_path = fixtures + "/similar-code/a.ts"
  let proto_source = @fs.read_file_to_string(proto_path) catch { _ => "" }
  let ts_source = @fs.read_file_to_string(ts_path) catch { _ => "" }
  if proto_source.length() == 0 || ts_source.length() == 0 {
    return
  }
  let files = [
    @batch.FileEntry::new("a.proto", proto_source),
    @batch.FileEntry::new("a.ts", ts_source),
  ]
  let result = @batch.compare_tfidf(files, 0.5)
  // Proto and TypeScript have very different vocabulary — should NOT match at 0.5.
  assert_eq(result.matches.length(), 0)
}

///|
test "similar-code: protobuf tokenization produces expected token kinds" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()
  let source = @fs.read_file_to_string(fixtures + "/similar-code/a.proto") catch {
    _ => ""
  }
  if source.length() == 0 {
    return
  }
  let spec = registry.get_spec("protobuf").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
  assert_true(tokens.length() > 0)
  assert_true(tokens.iter().any(fn(t) { t.kind == "KW_syntax" }))
  assert_true(tokens.iter().any(fn(t) { t.kind == "KW_package" }))
  assert_true(tokens.iter().any(fn(t) { t.kind == "KW_import" }))
  assert_true(tokens.iter().any(fn(t) { t.kind == "KW_message" }))
  assert_true(tokens.iter().any(fn(t) { t.kind == "KW_enum" }))
  assert_true(tokens.iter().any(fn(t) { t.kind == "KW_service" }))
  assert_true(tokens.iter().any(fn(t) { t.kind == "KW_rpc" }))
  assert_true(tokens.iter().any(fn(t) { t.kind == "KW_returns" }))
  assert_true(tokens.iter().any(fn(t) { t.kind == "KW_repeated" }))
  assert_true(tokens.iter().any(fn(t) { t.kind == "KW_optional" }))
  assert_true(tokens.iter().any(fn(t) { t.kind == "ScalarType" }))
}

///|
test "similar-code: protobuf pair declares same structure" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let fixtures = get_fixtures_dir()
  let a_source = @fs.read_file_to_string(fixtures + "/similar-code/a.proto") catch {
    _ => ""
  }
  let b_source = @fs.read_file_to_string(fixtures + "/similar-code/b.proto") catch {
    _ => ""
  }
  if a_source.length() == 0 || b_source.length() == 0 {
    return
  }
  let spec = registry.get_spec("protobuf").unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  // Count top-level declaration kinds in each file by tokenizing and parsing
  fn count_kind(source : String, kind : String) -> Int {
    let tokens = lexer.tokenize(source)
    let peg = @peg.build_peg(spec) catch { _ => return 0 }
    let start_rule = spec.get_start_rule()
    let parse_result = match @peg.run_parse(peg, spec, start_rule, tokens) {
      Some(r) => r
      None => return 0
    }
    let graph = @graph.CodeGraph::new()
    let _ = graph.get_or_add_module("test.proto", file=Some("test.proto"))
    let ctx = @semantics.SemEvalCtx::new(
      spec,
      graph,
      "test.proto",
      "",
      "protobuf",
      fn(_) { false },
    )
    for event in parse_result.get_events() {
      @semantics.eval_rule_semantics(event.0, event.1, ctx)
    }
    let mut count = 0
    for edge in graph.get_edges() {
      if !(edge.kind is @graph.Declares) {
        continue
      }
      if edge.attrs.get("kind").unwrap_or("") == kind {
        count += 1
      }
    }
    count
  }

  // Both files should have the same number of messages, enums, services, rpcs
  let a_messages = count_kind(a_source, "Message")
  let b_messages = count_kind(b_source, "Message")
  assert_eq(a_messages, b_messages)
  let a_enums = count_kind(a_source, "Enum")
  let b_enums = count_kind(b_source, "Enum")
  assert_eq(a_enums, b_enums)
  let a_services = count_kind(a_source, "Service")
  let b_services = count_kind(b_source, "Service")
  assert_eq(a_services, b_services)
  let a_rpcs = count_kind(a_source, "Rpc")
  let b_rpcs = count_kind(b_source, "Rpc")
  assert_eq(a_rpcs, b_rpcs)
}
