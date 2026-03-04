///|
/// Benchmark tests for PEG parser.
/// Run with: moon bench --target native -p trkbt10/indexion/src/kgf/peg

///|
/// Benchmark tokenizing (baseline comparison).
test "tokenize_large" (b : @bench.T) {
  let spec = @parser.parse_kgf(moonbit_kgf_content()).unwrap()
  let lexer_inst = @lexer.Lexer::new(spec.get_tokens())
  let src = large_source()
  b.bench(name="tokenize", fn() { b.keep(lexer_inst.tokenize(src)) })
}

///|
/// Benchmark PEG parsing (small file).
test "peg_parse_small" (b : @bench.T) {
  let spec = @parser.parse_kgf(moonbit_kgf_content()).unwrap()
  let lexer_inst = @lexer.Lexer::new(spec.get_tokens())
  let peg = build_peg(spec) catch { _ => PEG::new() }
  let active_rules = collect_active_rules(spec)
  let tokens = lexer_inst.tokenize(small_source())
  let start_rule = spec.get_start_rule()
  b.bench(name="parse_small", fn() {
    b.keep(run_parse_filtered(peg, spec, start_rule, tokens, active_rules))
  })
}

///|
/// Benchmark PEG parsing (large file).
test "peg_parse_large" (b : @bench.T) {
  let spec = @parser.parse_kgf(moonbit_kgf_content()).unwrap()
  let lexer_inst = @lexer.Lexer::new(spec.get_tokens())
  let peg = build_peg(spec) catch { _ => PEG::new() }
  let active_rules = collect_active_rules(spec)
  let tokens = lexer_inst.tokenize(large_source())
  let start_rule = spec.get_start_rule()
  b.bench(name="parse_large", fn() {
    b.keep(run_parse_filtered(peg, spec, start_rule, tokens, active_rules))
  })
}

// Helper functions for test data

fn moonbit_kgf_content() -> String {
  @fs.read_file_to_string("kgfs/moonbit.kgf") catch { _ => "" }
}

fn small_source() -> String {
  @fs.read_file_to_string("src/kgf/lexer/lexer.mbt") catch { _ => "" }
}

fn large_source() -> String {
  @fs.read_file_to_string("src/kgf/lexer/pattern_matcher.mbt") catch { _ => "" }
}
