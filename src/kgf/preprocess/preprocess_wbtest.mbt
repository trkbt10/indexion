///|
test "compile_char_class with single char" {
  let class = compile_char_class("test", "[a]")
  assert_eq(class.name, "test")
  assert_true(char_matches_class('a', class))
  assert_false(char_matches_class('b', class))
}

///|
test "compile_char_class with range" {
  let class = compile_char_class("alpha", "[A-Z]")
  assert_eq(class.name, "alpha")
  assert_true(char_matches_class('A', class))
  assert_true(char_matches_class('M', class))
  assert_true(char_matches_class('Z', class))
  assert_false(char_matches_class('a', class))
}

///|
test "compile_char_class with multiple ranges" {
  let class = compile_char_class("alphanum", "[A-Za-z0-9]")
  assert_true(char_matches_class('A', class))
  assert_true(char_matches_class('z', class))
  assert_true(char_matches_class('5', class))
  assert_false(char_matches_class('+', class))
}

///|
test "compile_char_class with mixed chars and ranges" {
  let class = compile_char_class("base64", "[A-Za-z0-9+/=]")
  assert_true(char_matches_class('A', class))
  assert_true(char_matches_class('z', class))
  assert_true(char_matches_class('0', class))
  assert_true(char_matches_class('+', class))
  assert_true(char_matches_class('/', class))
  assert_true(char_matches_class('=', class))
  assert_false(char_matches_class('!', class))
}

///|
test "sextet values for base64 characters" {
  // A-Z: 0-25
  assert_eq(sextet('A'), Some(0))
  assert_eq(sextet('Z'), Some(25))
  // a-z: 26-51
  assert_eq(sextet('a'), Some(26))
  assert_eq(sextet('z'), Some(51))
  // 0-9: 52-61
  assert_eq(sextet('0'), Some(52))
  assert_eq(sextet('9'), Some(61))
  // + and -: 62
  assert_eq(sextet('+'), Some(62))
  assert_eq(sextet('-'), Some(62))
  // / and _: 63
  assert_eq(sextet('/'), Some(63))
  assert_eq(sextet('_'), Some(63))
  // Invalid
  assert_eq(sextet('!'), None)
}

///|
test "decode_quartet basic" {
  // "AAAA" -> [0, 0, 0]
  let sextets = [0, 0, 0, 0]
  let bytes = decode_quartet(sextets, 0)
  assert_eq(bytes.length(), 3)
  assert_eq(bytes[0], 0)
  assert_eq(bytes[1], 0)
  assert_eq(bytes[2], 0)
}

///|
test "decode_quartet with padding 1" {
  // With pad=1, returns 2 bytes
  let sextets = [0, 0, 0, 0]
  let bytes = decode_quartet(sextets, 1)
  assert_eq(bytes.length(), 2)
}

///|
test "decode_quartet with padding 2" {
  // With pad=2, returns 1 byte
  let sextets = [0, 0, 0, 0]
  let bytes = decode_quartet(sextets, 2)
  assert_eq(bytes.length(), 1)
}

///|
test "classify_utf8 ASCII" {
  // Pure ASCII printable
  let bytes = [65, 66, 67] // "ABC"
  let result = classify_utf8(bytes)
  assert_eq(utf8_agg_to_string(result), "A")
}

///|
test "classify_utf8 with whitespace" {
  // ASCII with whitespace
  let bytes = [65, 32, 66] // "A B"
  let result = classify_utf8(bytes)
  assert_eq(utf8_agg_to_string(result), "W")
}

///|
test "classify_utf8 with control chars" {
  // ASCII with control char (bell)
  let bytes = [65, 7, 66] // "A\x07B"
  let result = classify_utf8(bytes)
  assert_eq(utf8_agg_to_string(result), "C")
}

///|
test "classify_utf8 multibyte" {
  // UTF-8 multibyte: U+00E9 (e with acute) = 0xC3 0xA9
  let bytes = [0xc3, 0xa9]
  let result = classify_utf8(bytes)
  assert_eq(utf8_agg_to_string(result), "U")
}

///|
test "classify_utf8 invalid" {
  // Invalid: continuation byte at start
  let bytes = [0x80]
  let result = classify_utf8(bytes)
  assert_eq(utf8_agg_to_string(result), "X")
}

///|
test "base64_to_hex simple" {
  // "SGVsbG8=" -> "Hello" -> hex
  let result = base64_to_hex("SGVsbG8=")
  // H=0x48, e=0x65, l=0x6C, l=0x6C, o=0x6F
  assert_eq(result, "48656C6C6F")
}

///|
test "base64_to_hex AA" {
  // "AA==" -> 0x00
  let result = base64_to_hex("AA==")
  assert_eq(result, "00")
}

///|
test "compile_fst simple" {
  let classes : Map[String, String] = {}
  classes.set("alpha", "[A-Za-z]")
  classes.set("ws", "[ ]")
  let states : Map[String, Array[@types.FstTransition]] = {}
  states.set("start", [
    @types.FstTransition::new("alpha", "start", [@types.FstAction::emit_input()]),
    @types.FstTransition::new("ws", "start", [@types.FstAction::emit(" ")]),
  ])
  let spec = @types.PreprocessFstSpec::new("test", classes, "start", states)
  let fst = compile_fst(spec)
  assert_eq(fst.name, "test")
  assert_eq(fst.initial, "start")
  assert_eq(fst.classes.length(), 2)
}

///|
test "run_fst simple passthrough" {
  let classes : Map[String, String] = {}
  classes.set("any", "[A-Za-z ]")
  let states : Map[String, Array[@types.FstTransition]] = {}
  states.set("start", [
    @types.FstTransition::new("any", "start", [@types.FstAction::emit_input()]),
  ])
  let spec = @types.PreprocessFstSpec::new(
    "passthrough", classes, "start", states,
  )
  let fst = compile_fst(spec)
  let result = run_fst(fst, "Hello World")
  assert_eq(result, "Hello World")
}

///|
test "run_fst emit replacement" {
  let classes : Map[String, String] = {}
  classes.set("alpha", "[A-Za-z]")
  classes.set("space", "[ ]")
  let states : Map[String, Array[@types.FstTransition]] = {}
  states.set("start", [
    @types.FstTransition::new("alpha", "start", [@types.FstAction::emit("X")]),
    @types.FstTransition::new("space", "start", [@types.FstAction::emit_input()]),
  ])
  let spec = @types.PreprocessFstSpec::new("replace", classes, "start", states)
  let fst = compile_fst(spec)
  let result = run_fst(fst, "Hi There")
  assert_eq(result, "XX XXXXX")
}

///|
test "apply_preprocess with no steps" {
  let result = apply_preprocess("test input", None, None)
  assert_eq(result, "test input")
}

///|
test "apply_preprocess with empty steps" {
  let result = apply_preprocess("test input", Some([]), None)
  assert_eq(result, "test input")
}

///|
test "apply_preprocess with base64ToHex" {
  let result = apply_preprocess("SGVsbG8=", Some(["base64ToHex"]), None)
  assert_eq(result, "48656C6C6F")
}

///|
test "apply_preprocess with generic line blanking steps" {
  let input = "RFC 3492\nbody [Page 1]\nkeep\n\u{000c}footer\n"
  let result = apply_preprocess(
    input,
    Some([
      "blankLineIfTrimHasPrefix:RFC ", "blankLineIfContains:[Page ", "blankLineIfContainsCodepoint:000c",
    ]),
    None,
  )
  assert_eq(result, "\n\nkeep\n\n")
}

///|
test "apply_preprocess with FST" {
  let classes : Map[String, String] = {}
  classes.set("any", "[A-Za-z ]")
  let states : Map[String, Array[@types.FstTransition]] = {}
  states.set("start", [
    @types.FstTransition::new("any", "start", [@types.FstAction::emit_input()]),
  ])
  let spec = @types.PreprocessFstSpec::new(
    "passthrough", classes, "start", states,
  )
  let result = apply_preprocess(
    "Hello",
    Some(["fst:passthrough"]),
    Some([spec]),
  )
  assert_eq(result, "Hello")
}

///|
test "apply_preprocess with blankLineIfRegex" {
  let input = "ISO 32000-2:2020(E) \n42\nkeep this\n123\nAnother line\n"
  let result = apply_preprocess(
    input,
    Some([
      "blankLineIfRegex:^ISO[\\s_/-]\\d+", "blankLineIfRegex:^\\d{1,3}\\s*$",
    ]),
    None,
  )
  assert_eq(result, "\n\nkeep this\n\nAnother line\n")
}
