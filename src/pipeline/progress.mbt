///|
/// Write a UTF-8 byte run to stderr.
#borrow(bytes)
extern "C" fn c_progress_eprint(bytes : Bytes, len : Int) = "indexion_progress_eprint"

///|
extern "C" fn c_progress_eflush() = "indexion_progress_eflush"

///|
/// Write `msg` followed by a newline to stderr, flushing immediately.
///
/// Use this for progress / timing diagnostics so stdout stays clean for the
/// report payload (which may be piped to a file or another tool).
pub fn eprintln(msg : String) -> Unit {
  let with_newline = msg + "\n"
  let bytes = @utf8.encode(with_newline)
  c_progress_eprint(bytes, bytes.length())
  c_progress_eflush()
}

///|
/// Milliseconds since the unix epoch — start of a span.
pub fn now_ms() -> UInt64 {
  @env.now()
}

///|
/// Elapsed milliseconds since `start`. Saturates at zero if the clock moved
/// backwards (system clock adjustment) rather than wrapping.
pub fn elapsed_ms(start : UInt64) -> UInt64 {
  let now = @env.now()
  if now >= start {
    now - start
  } else {
    0UL
  }
}

///|
/// Emit a single timed stage line:
///   `[orient] discover  done  files=1900  in=1234ms`
pub fn stage(label : String, detail : String, elapsed_ms : UInt64) -> Unit {
  let buf = StringBuilder::new()
  buf.write_string(label)
  if detail.length() > 0 {
    buf.write_string("  ")
    buf.write_string(detail)
  }
  buf.write_string("  in=")
  buf.write_string(elapsed_ms.to_string())
  buf.write_string("ms")
  eprintln(buf.to_string())
}
