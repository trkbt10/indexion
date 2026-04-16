///|
test "SourceMap resolves LF offsets" {
  let source_map = SourceMap::new("hello\nworld")
  assert_eq(source_map.resolve(0), (1, 1))
  assert_eq(source_map.resolve(6), (2, 1))
}

///|
test "SourceMap resolves CRLF offsets" {
  let source_map = SourceMap::new("hello\r\nworld")
  assert_eq(source_map.resolve(0), (1, 1))
  assert_eq(source_map.resolve(7), (2, 1))
}

///|
test "SourceMap handles empty input" {
  let source_map = SourceMap::new("")
  assert_eq(source_map.resolve(0), (1, 1))
}
