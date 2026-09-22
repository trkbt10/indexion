///|
/// Wall-clock time utilities shared by CLI commands.

///|
/// Format an epoch-milliseconds instant as ISO 8601 UTC
/// (`YYYY-MM-DDTHH:MM:SSZ`). Returns `None` when the instant cannot be
/// represented by the time library.
pub fn iso8601_utc_from_ms(ms : UInt64) -> String? {
  let seconds = (ms / 1000UL).reinterpret_as_int64()
  let zdt = @time.unix(seconds, zone=@time.utc_zone) catch { _ => return None }
  Some(
    pad_int(zdt.year(), 4) +
    "-" +
    pad_int(zdt.month(), 2) +
    "-" +
    pad_int(zdt.day(), 2) +
    "T" +
    pad_int(zdt.hour(), 2) +
    ":" +
    pad_int(zdt.minute(), 2) +
    ":" +
    pad_int(zdt.second(), 2) +
    "Z",
  )
}

///|
/// Current wall-clock time as ISO 8601 UTC.
pub fn now_iso8601_utc() -> String? {
  iso8601_utc_from_ms(@env.now())
}

///|
/// Left-pad a non-negative integer with zeros to a minimum width.
fn pad_int(n : Int, width : Int) -> String {
  let digits = n.to_string()
  let buf = StringBuilder()
  let mut missing = width - digits.length()
  while missing > 0 {
    buf.write_string("0")
    missing = missing - 1
  }
  buf.write_string(digits)
  buf.to_string()
}
