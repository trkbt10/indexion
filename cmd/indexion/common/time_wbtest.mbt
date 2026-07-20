///|
/// Tests for wall-clock time utilities.

///|
test "iso8601_utc_from_ms formats the unix epoch" {
  assert_eq(iso8601_utc_from_ms(0UL), Some("1970-01-01T00:00:00Z"))
}

///|
test "iso8601_utc_from_ms formats a positive instant with padding" {
  // 1970-01-02 03:04:05 UTC = 86400 + 3*3600 + 4*60 + 5 seconds
  let ms = (86400UL + 3UL * 3600UL + 4UL * 60UL + 5UL) * 1000UL
  assert_eq(iso8601_utc_from_ms(ms), Some("1970-01-02T03:04:05Z"))
}
