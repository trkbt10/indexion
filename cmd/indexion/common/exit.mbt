///|
/// Cross-target process exit. The trailing `panic()` on the native path is
/// unreachable — `native_exit` terminates the process — but satisfies the
/// `Unit` return type without introducing a value.

///|
#cfg(any(target="native", target="llvm"))
extern "c" fn native_exit(code : Int) = "exit"

///|
#cfg(any(target="native", target="llvm"))
pub fn exit_with_code(code : Int) -> Unit {
  native_exit(code)
  panic()
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
fn wasm_exit(code : Int) -> Unit = "__moonbit_sys_unstable" "exit"

///|
#cfg(any(target="wasm", target="wasm-gc"))
pub fn exit_with_code(code : Int) -> Unit {
  wasm_exit(code)
}

///|
#cfg(target="js")
extern "js" fn js_try_exit(code : Int) -> Bool =
  #| () => {
  #|   if (typeof process !== "undefined" && typeof process.exit === "function") {
  #|     process.exit(code);
  #|     return true;
  #|   }
  #|   return false;
  #| }

///|
#cfg(target="js")
pub fn exit_with_code(code : Int) -> Unit {
  if !js_try_exit(code) {
    panic()
  }
}
