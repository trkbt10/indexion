///|
/// Benchmark tests for pipeline stages.
/// Run with: moon bench --target native -p trkbt10/indexion/src/pipeline

///|
/// Benchmark file discovery on src/ directory.
test "discover_files" (b : @bench.T) {
  let paths = ["src/"]
  let options = DiscoverOptions::default()
  b.bench(name="discover_src", fn() { b.keep(discover_files(paths, options)) })
}

///|
/// Benchmark KGF spec loading and selection.
test "load_registry" (b : @bench.T) {
  let paths = ["src/"]
  let options = DiscoverOptions::default()
  let file_paths = discover_files(paths, options)
  b.bench(name="load_registry", fn() {
    b.keep(load_registry_for_paths("kgfs", file_paths))
  })
}

///|
/// Benchmark collect supported files (includes file I/O).
test "collect_supported" (b : @bench.T) {
  let paths = ["src/kgf/lexer/"]
  let options = DiscoverOptions::default()
  let file_paths = discover_files(paths, options)
  let registry = load_registry_for_paths("kgfs", file_paths)
  b.bench(name="collect_files", fn() {
    b.keep(collect_supported_files(file_paths, registry))
  })
}

///|
/// Benchmark KGF spec file reading only (no parsing).
test "kgf_file_read" (b : @bench.T) {
  b.bench(
    name="read_moonbit_kgf",
    fn() {
      let content = @fs.read_file_to_string("kgfs/moonbit.kgf") catch { _ => "" }
      b.keep(content)
    },
  )
}

///|
/// Benchmark KGF parsing (single spec).
test "kgf_parse_single" (b : @bench.T) {
  let content = @fs.read_file_to_string("kgfs/moonbit.kgf") catch { _ => "" }
  b.bench(name="parse_moonbit_kgf", fn() {
    b.keep(@kgf_parser.parse_kgf(content))
  })
}

///|
/// Benchmark building path signals.
test "build_signals" (b : @bench.T) {
  let paths = ["src/"]
  let options = DiscoverOptions::default()
  let file_paths = discover_files(paths, options)
  b.bench(name="build_path_signals", fn() {
    b.keep(build_path_signals(file_paths))
  })
}

///|
/// Benchmark parsing all KGF specs (without signal matching).
test "parse_all_kgf" (b : @bench.T) {
  // Read all KGF file contents first
  let kgf_contents : Array[(String, String)] = []
  let entries = @fs.read_dir("kgfs") catch { _ => [] }
  for entry in entries {
    if entry.has_suffix(".kgf") {
      let path = "kgfs/" + entry
      let content = @fs.read_file_to_string(path) catch { _ => continue }
      kgf_contents.push((entry, content))
    }
  }
  b.bench(name="parse_all_kgf", fn() {
    let mut count = 0
    for entry in kgf_contents {
      let _ = @kgf_parser.parse_kgf(entry.1)
      count = count + 1
    }
    b.keep(count)
  })
}

///|
/// Benchmark reading all KGF files.
test "read_all_kgf" (b : @bench.T) {
  let entries = @fs.read_dir("kgfs") catch { _ => [] }
  let kgf_entries : Array[String] = []
  for entry in entries {
    if entry.has_suffix(".kgf") {
      kgf_entries.push(entry)
    }
  }
  b.bench(name="read_all_kgf", fn() {
    let mut count = 0
    for entry in kgf_entries {
      let path = "kgfs/" + entry
      let _ = @fs.read_file_to_string(path) catch { _ => continue }
      count = count + 1
    }
    b.keep(count)
  })
}

///|
/// Benchmark Lexer construction from parsed KGF spec.
test "lexer_build" (b : @bench.T) {
  let content = @fs.read_file_to_string("kgfs/moonbit.kgf") catch { _ => "" }
  let spec = @kgf_parser.parse_kgf(content).unwrap()
  let tokens = spec.get_tokens()
  b.bench(name="lexer_build", fn() { b.keep(@kgf_lexer.Lexer::new(tokens)) })
}

///|
/// Benchmark PEG construction from parsed KGF spec.
test "peg_build" (b : @bench.T) {
  let content = @fs.read_file_to_string("kgfs/moonbit.kgf") catch { _ => "" }
  let spec = @kgf_parser.parse_kgf(content).unwrap()
  b.bench(name="peg_build", fn() {
    let peg = @kgf_peg.build_peg(spec) catch { _ => @kgf_peg.PEG::new() }
    b.keep(peg)
  })
}

///|
/// Benchmark full pipeline: parse KGF + build Lexer + build PEG.
test "full_spec_build" (b : @bench.T) {
  let content = @fs.read_file_to_string("kgfs/moonbit.kgf") catch { _ => "" }
  b.bench(name="full_spec_build", fn() {
    let spec = @kgf_parser.parse_kgf(content).unwrap()
    let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
    let peg = @kgf_peg.build_peg(spec) catch { _ => @kgf_peg.PEG::new() }
    b.keep((lexer, peg))
  })
}

///|
/// Benchmark building KGF index (headers only).
test "build_kgf_index" (b : @bench.T) {
  b.bench(name="build_kgf_index", fn() { b.keep(build_kgf_index("kgfs")) })
}

///|
/// Benchmark load_registry using index (2-step).
test "load_registry_with_index" (b : @bench.T) {
  let paths = ["src/"]
  let options = DiscoverOptions::default()
  let file_paths = discover_files(paths, options)
  let signals = build_path_signals(file_paths)
  // Pre-build index
  let index = build_kgf_index("kgfs")
  b.bench(name="load_from_index", fn() {
    b.keep(load_registry_from_index(index, signals))
  })
}

///|
/// Benchmark tokenizing a single file.
test "tokenize_single_file" (b : @bench.T) {
  let content = @fs.read_file_to_string("kgfs/moonbit.kgf") catch { _ => "" }
  let spec = @kgf_parser.parse_kgf(content).unwrap()
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let src = @fs.read_file_to_string("src/kgf/lexer/lexer.mbt") catch { _ => "" }
  b.bench(name="tokenize", fn() { b.keep(lexer.tokenize(src)) })
}

///|
/// Benchmark PEG parsing a single file (small).
test "peg_parse_single_file" (b : @bench.T) {
  let content = @fs.read_file_to_string("kgfs/moonbit.kgf") catch { _ => "" }
  let spec = @kgf_parser.parse_kgf(content).unwrap()
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let peg = @kgf_peg.build_peg(spec) catch { _ => @kgf_peg.PEG::new() }
  let active_rules = @kgf_peg.collect_active_rules(spec)
  let src = @fs.read_file_to_string("src/kgf/lexer/lexer.mbt") catch { _ => "" }
  let tokens = lexer.tokenize(src)
  let start_rule = spec.get_start_rule()
  b.bench(name="peg_parse", fn() {
    b.keep(@kgf_peg.run_parse_filtered(peg, spec, start_rule, tokens, active_rules))
  })
}

///|
/// Benchmark PEG parsing a large file (28KB).
test "peg_parse_large_file" (b : @bench.T) {
  let content = @fs.read_file_to_string("kgfs/moonbit.kgf") catch { _ => "" }
  let spec = @kgf_parser.parse_kgf(content).unwrap()
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let peg = @kgf_peg.build_peg(spec) catch { _ => @kgf_peg.PEG::new() }
  let active_rules = @kgf_peg.collect_active_rules(spec)
  let src = @fs.read_file_to_string("src/kgf/lexer/pattern_matcher.mbt") catch {
    _ => ""
  }
  let tokens = lexer.tokenize(src)
  let start_rule = spec.get_start_rule()
  b.bench(name="peg_parse_large", fn() {
    b.keep(@kgf_peg.run_parse_filtered(peg, spec, start_rule, tokens, active_rules))
  })
}
