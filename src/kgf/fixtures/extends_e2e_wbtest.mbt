// End-to-end test for spec inheritance: two specs written to a scratch
// directory, loaded through `KGFRegistry::load_from_dir`, with the derived
// spec's own semantics producing edges from the *inherited* grammar.
//
// The unit tests cover merging; this one covers the whole path a real spec
// takes — files on disk, two-phase directory load, lexer and PEG built from
// the merged sections, semantic evaluation into a code graph.

///|
/// Base spec: lex + grammar only, no semantics of its own.
let e2e_base_spec : String =
  #|kgf 0.6
  #|language: e2e-base
  #|sources: .e2ebase
  #|
  #|=== lex
  #|SKIP /[ \t\r\n]+/
  #|TOKEN KW_needs /needs\b/
  #|TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/
  #|TOKEN SEMI /;/
  #|
  #|=== grammar
  #|Doc -> Item*
  #|Item -> NeedsDecl
  #|NeedsDecl -> KW_needs target:Ident SEMI
  #|
  #|=== resolver
  #|relative_prefixes: ./
  #|module_path_style: slash

///|
/// Derived spec: inherits lex + grammar + resolver, adds only semantics.
/// This is the shape the shipped duplicate specs are meant to collapse to.
let e2e_derived_spec : String =
  #|kgf 0.6
  #|language: e2e-derived
  #|sources: .e2ederived
  #|extends: e2e-base
  #|
  #|=== semantics
  #|on NeedsDecl {
  #|  edge moduleDependsOn from $file to $target attrs obj("via", $target)
  #|}

///|
/// Write a scratch spec file, creating parent directories as needed.
fn write_scratch_spec(path : String, content : String) -> Unit {
  @config_paths.ensure_parent_dir(path)
  @fs.write_string_to_file(path, content) catch {
    _ => panic()
  }
}

///|
/// Run a source file through a resolved spec and collect the edge kinds and
/// targets it produces.
fn collect_edges(
  spec : @kgf_types.KGFSpec,
  source : String,
  path : String,
) -> Array[(String, String)] {
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
  let peg = @peg.build_peg(spec) catch { _ => return [] }
  let parse_result = match
    @peg.run_parse(peg, spec, spec.get_start_rule(), tokens) {
    Some(result) => result
    None => return []
  }
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(path, file=Some(path))
  let ctx = @semantics.SemEvalCtx::new(
    spec,
    graph,
    path,
    "",
    spec.get_language(),
    fn(_) { false },
  )
  for event in parse_result.get_events() {
    @semantics.eval_rule_semantics(event.0, event.1, ctx)
  }
  let edges : Array[(String, String)] = []
  for edge in graph.get_edges() {
    edges.push((edge.kind.to_string(), edge.to))
  }
  edges
}

///|
test "extends end-to-end: derived spec builds edges from the inherited grammar" {
  let scratch = @config_paths.join_path(
    @config_paths.get_global_cache_dir().unwrap_or("."),
    "kgf_extends_e2e",
  )
  // Put the base in a subdirectory so the base is only reachable after the
  // recursive walk has already passed the derived spec — the situation that
  // forces resolution to happen after the whole directory is loaded.
  write_scratch_spec(scratch + "/derived.kgf", e2e_derived_spec)
  write_scratch_spec(scratch + "/base/base.kgf", e2e_base_spec)
  let registry = @registry.KGFRegistry::load_from_dir(scratch)
  assert_eq(registry.spec_count(), 2)

  // Both specs keep their own header identity.
  let derived = registry.get_spec("e2e-derived").unwrap()
  assert_eq(derived.get_extends(), Some("e2e-base"))
  assert_eq(registry.get_lang_from_ext(".e2ederived"), Some("e2e-derived"))
  assert_eq(registry.get_lang_from_ext(".e2ebase"), Some("e2e-base"))

  // The derived spec parses with the inherited lexer and grammar...
  let source = "needs alpha; needs beta;"
  let edges = collect_edges(derived, source, "doc.e2ederived")
  // ...and its own semantics turn that parse into edges.
  assert_eq(edges.length(), 2)
  // `EdgeKind` canonicalises the spec's `moduleDependsOn` to snake case.
  assert_eq(
    edges[0].0,
    @graph.EdgeKind::from_string("moduleDependsOn").to_string(),
  )
  assert_eq(edges[0].1, "alpha")
  assert_eq(edges[1].1, "beta")

  // The base declares no semantics, so the same input yields no edges there —
  // proof the semantics really came from the derived spec, not the base.
  let base = registry.get_spec("e2e-base").unwrap()
  assert_eq(collect_edges(base, source, "doc.e2ebase").length(), 0)
}
