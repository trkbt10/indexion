///|
using @test {assert_eq}

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

///|
test "SourceMap resolves middle and end offsets with binary search" {
  let source_map = SourceMap::new("a\nbc\ndef")
  assert_eq(source_map.get_line_starts(), [0, 2, 5])
  assert_eq(source_map.resolve(3), (2, 2))
  assert_eq(source_map.resolve(8), (3, 4))
}

///|
test "SourceMap clamps negative offsets" {
  let source_map = SourceMap::new("hello\nworld")
  assert_eq(source_map.resolve(-1), (1, 1))
}
