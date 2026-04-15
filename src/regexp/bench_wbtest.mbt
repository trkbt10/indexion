///|
/// Benchmark tests for regexp engine.
/// Run with: moon bench --target native -p trkbt10/indexion/src/regexp

// --- Test data generators ---

///|
fn short_input() -> String {
  "import foo from 'bar'"
}

///|
fn medium_input() -> String {
  let buf = StringBuilder::new()
  for i = 0; i < 100; i = i + 1 {
    buf.write_string("let variable_")
    buf.write_string(i.to_string())
    buf.write_string(" = function(arg1, arg2) { return arg1 + arg2; };\n")
  }
  buf.to_string()
}

///|
fn large_input() -> String {
  let buf = StringBuilder::new()
  for i = 0; i < 1000; i = i + 1 {
    buf.write_string("pub fn process_item_")
    buf.write_string(i.to_string())
    buf.write_string(
      "(input : String, count : Int) -> Result[String, Error] {\n",
    )
    buf.write_string("  let result = input.to_string()\n")
    buf.write_string("  if count > 0 { Ok(result) } else { Err(Error) }\n")
    buf.write_string("}\n\n")
  }
  buf.to_string()
}

///|
fn block_comment_input() -> String {
  let buf = StringBuilder::new()
  for i = 0; i < 50; i = i + 1 {
    buf.write_string("/** Documentation for function_")
    buf.write_string(i.to_string())
    buf.write_string(
      ".\n * @param x the input value\n * @returns the result\n */\n",
    )
    buf.write_string("fn function_")
    buf.write_string(i.to_string())
    buf.write_string("(x : Int) -> Int { x + 1 }\n\n")
  }
  buf.to_string()
}

// --- Compile benchmarks ---

///|
test "compile: literal pattern" (b : @bench.T) {
  b.bench(name="compile_literal", fn() { b.keep(compile_pattern("hello")) })
}

///|
test "compile: char class pattern" (b : @bench.T) {
  b.bench(name="compile_charclass", fn() {
    b.keep(compile_pattern("[a-zA-Z_][a-zA-Z0-9_]*"))
  })
}

///|
test "compile: complex pattern with groups" (b : @bench.T) {
  b.bench(name="compile_complex", fn() {
    b.keep(compile_pattern("(foo)=(\\d+)"))
  })
}

///|
test "compile: alternation pattern" (b : @bench.T) {
  b.bench(name="compile_alternation", fn() {
    b.keep(compile_pattern("import|export|from|require"))
  })
}

///|
test "compile: block comment pattern" (b : @bench.T) {
  b.bench(name="compile_block_comment", fn() {
    b.keep(compile_pattern("\\/\\*\\*[\\s\\S]*?\\*\\/"))
  })
}

// --- Single match benchmarks ---

///|
test "match: literal short input" (b : @bench.T) {
  let compiled = compile_pattern("import").unwrap()
  let input = short_input()
  let chars = build_input_chars(input)
  b.bench(name="match_literal_short", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}

///|
test "match: word class on identifier" (b : @bench.T) {
  let compiled = compile_pattern("\\w+").unwrap()
  let input = "hello_world_variable123"
  let chars = build_input_chars(input)
  b.bench(name="match_word_class", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}

///|
test "match: char class identifier" (b : @bench.T) {
  let compiled = compile_pattern("[a-zA-Z_][a-zA-Z0-9_]*").unwrap()
  let input = "my_variable_name_123"
  let chars = build_input_chars(input)
  b.bench(name="match_charclass_ident", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}

///|
test "match: digits with quantifier" (b : @bench.T) {
  let compiled = compile_pattern("\\d+").unwrap()
  let input = "1234567890abcdef"
  let chars = build_input_chars(input)
  b.bench(name="match_digits", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}

///|
test "match: hex color {n}" (b : @bench.T) {
  let compiled = compile_pattern("#[0-9a-fA-F]{6}").unwrap()
  let input = "#ff00aa rest"
  let chars = build_input_chars(input)
  b.bench(name="match_hex_color", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}

///|
test "match: number pattern with non-capturing group" (b : @bench.T) {
  let compiled = compile_pattern("(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?").unwrap()
  let input = "123.456 rest"
  let chars = build_input_chars(input)
  b.bench(name="match_number_noncap", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}

///|
test "match: word boundary" (b : @bench.T) {
  let compiled = compile_pattern("import\\b").unwrap()
  let input = "import foo from 'bar'"
  let chars = build_input_chars(input)
  b.bench(name="match_word_boundary", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}

///|
test "match: positive lookahead" (b : @bench.T) {
  let compiled = compile_pattern("[a-z]+(?=\\s*=)").unwrap()
  let input = "name = value"
  let chars = build_input_chars(input)
  b.bench(name="match_pos_lookahead", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}

///|
test "match: alternation 4 branches" (b : @bench.T) {
  let compiled = compile_pattern("import|export|from|require").unwrap()
  let input = "require('module')"
  let chars = build_input_chars(input)
  b.bench(name="match_alt_4", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}

///|
test "match: first char filter rejection" (b : @bench.T) {
  let compiled = compile_pattern("import").unwrap()
  let input = "xxxxxxxxxx"
  let chars = build_input_chars(input)
  b.bench(name="match_reject_firstchar", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}

// --- Block comment (lazy quantifier + backtracking) ---

///|
test "match: block comment pattern" (b : @bench.T) {
  let compiled = compile_pattern("\\/\\*\\*[\\s\\S]*?\\*\\/").unwrap()
  let input = "/** Hello world */\nexport"
  let chars = build_input_chars(input)
  b.bench(name="match_block_comment", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}

// --- Scan (find_pattern_captures) benchmarks ---

///|
test "scan: digits in medium input" (b : @bench.T) {
  let input = medium_input()
  b.bench(name="scan_digits_medium", fn() {
    b.keep(find_pattern_captures("\\d+", input))
  })
}

///|
test "scan: identifiers in medium input" (b : @bench.T) {
  let input = medium_input()
  b.bench(name="scan_ident_medium", fn() {
    b.keep(find_pattern_captures("[a-zA-Z_][a-zA-Z0-9_]*", input))
  })
}

///|
test "scan: word boundary keyword in medium" (b : @bench.T) {
  let input = medium_input()
  b.bench(name="scan_keyword_medium", fn() {
    b.keep(find_pattern_captures("\\bfunction\\b", input))
  })
}

///|
test "scan: capture groups in medium" (b : @bench.T) {
  let input = medium_input()
  b.bench(name="scan_captures_medium", fn() {
    b.keep(find_pattern_captures("(\\w+)\\s*=\\s*(\\w+)", input))
  })
}

///|
test "scan: block comments in comment input" (b : @bench.T) {
  let input = block_comment_input()
  b.bench(name="scan_block_comments", fn() {
    b.keep(find_pattern_captures("\\/\\*\\*[\\s\\S]*?\\*\\/", input))
  })
}

///|
test "scan: pub fn in large input" (b : @bench.T) {
  let input = large_input()
  b.bench(name="scan_pub_fn_large", fn() {
    b.keep(find_pattern_captures("pub\\s+fn\\s+(\\w+)", input))
  })
}

///|
test "scan: alternation keywords in large" (b : @bench.T) {
  let input = large_input()
  b.bench(name="scan_alt_keywords_large", fn() {
    b.keep(find_pattern_captures("\\b(?:pub|fn|let|if|else|return)\\b", input))
  })
}

// --- build_input_chars benchmark ---

///|
test "build_input_chars: medium" (b : @bench.T) {
  let input = medium_input()
  b.bench(name="build_chars_medium", fn() { b.keep(build_input_chars(input)) })
}

///|
test "build_input_chars: large" (b : @bench.T) {
  let input = large_input()
  b.bench(name="build_chars_large", fn() { b.keep(build_input_chars(input)) })
}

// --- Worst-case / pathological patterns ---

///|
test "match: nested quantifiers (a+)+ non-pathological" (b : @bench.T) {
  let compiled = compile_pattern("(a+)+b").unwrap()
  let input = "aaaaaaaaab"
  let chars = build_input_chars(input)
  b.bench(name="match_nested_quant_ok", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}

///|
test "match: case insensitive" (b : @bench.T) {
  let compiled = compile_pattern("hello", case_insensitive=true).unwrap()
  let input = "HELLO WORLD"
  let chars = build_input_chars(input)
  b.bench(name="match_case_insensitive", fn() {
    b.keep(match_compiled_end_pos_with_chars(compiled, chars, 0))
  })
}
