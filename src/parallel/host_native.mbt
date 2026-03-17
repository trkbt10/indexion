///|
extern "C" fn c_parallel_fork() -> Int = "indexion_parallel_fork"

///|
extern "C" fn c_parallel_waitpid(pid : Int) -> Int = "indexion_parallel_waitpid"

///|
extern "C" fn c_parallel_exit(code : Int) = "indexion_parallel_exit"

///|
extern "C" fn c_parallel_getpid() -> Int = "indexion_parallel_getpid"

///|
extern "C" fn c_parallel_flush_stdio() = "indexion_parallel_flush_stdio"

///|
#borrow(path)
extern "C" fn c_parallel_mkdir(path : Bytes, path_len : Int) -> Int = "indexion_parallel_mkdir"

///|
#borrow(path)
extern "C" fn c_parallel_unlink(path : Bytes, path_len : Int) -> Int = "indexion_parallel_unlink"

///|
#borrow(path)
extern "C" fn c_parallel_rmdir(path : Bytes, path_len : Int) -> Int = "indexion_parallel_rmdir"

///|
extern "C" fn c_parallel_cpu_count() -> Int = "indexion_parallel_cpu_count"

///|
fn encode_bytes(text : String) -> Bytes {
  @utf8.encode(text)
}

///|
fn fork_native() -> Int {
  c_parallel_fork()
}

///|
fn waitpid_native(pid : Int) -> Int {
  c_parallel_waitpid(pid)
}

///|
fn exit_now(code : Int) -> Unit {
  c_parallel_exit(code)
}

///|
fn getpid_native() -> Int {
  c_parallel_getpid()
}

///|
fn flush_stdio_native() -> Unit {
  c_parallel_flush_stdio()
}

///|
fn mkdir_native(path : String) -> Int {
  let bytes = encode_bytes(path)
  c_parallel_mkdir(bytes, bytes.length())
}

///|
fn unlink_native(path : String) -> Int {
  let bytes = encode_bytes(path)
  c_parallel_unlink(bytes, bytes.length())
}

///|
fn rmdir_native(path : String) -> Int {
  let bytes = encode_bytes(path)
  c_parallel_rmdir(bytes, bytes.length())
}

///|
fn cpu_count_native() -> Int {
  c_parallel_cpu_count()
}

///|
fn parallel_available_native() -> Bool {
  true
}
