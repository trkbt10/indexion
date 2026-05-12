///|
/// Whether fork-based parallelism is available on this platform.
pub fn available() -> Bool {
  parallel_available_native()
}

///|
/// Return the number of available CPU cores.
pub fn cpu_count() -> Int {
  cpu_count_native()
}

///|
/// Exit the current process immediately with the given status code.
pub fn exit(code : Int) -> Unit {
  flush_stdio_native()
  exit_now(code)
}

///|
/// Return the OS-level process id of the running indexion process. Used by the
/// orient cache lock to record ownership so a crashed process can be diagnosed
/// before a stale lock is taken over. Returns a negative value on platforms
/// that do not implement `getpid` (only the wasm/js stubs).
pub fn pid() -> Int {
  getpid_native()
}

///|
/// Run multiple tasks in parallel using fork.
/// Each task returns a String (typically serialized JSON).
/// Falls back to sequential execution if fork is unavailable.
pub fn run_parallel(tasks : Array[() -> String]) -> Array[String] {
  if tasks.length() == 0 {
    return []
  }
  if tasks.length() == 1 || !available() {
    let results : Array[String] = []
    for task in tasks {
      results.push(task())
    }
    return results
  }
  flush_stdio_native()
  let base = match @config.get_global_cache_dir() {
    Some(d) => d
    None => "/tmp"
  }
  let dir = base + "/parallel_" + getpid_native().to_string()
  let _ = mkdir_native(dir)
  let workers : Array[(Int, String)] = []
  let mut all_forked = true
  for i, task in tasks {
    let path = dir + "/r" + i.to_string()
    let pid = fork_native()
    if pid == 0 {
      // Child process
      let result = task()
      @fs.write_string_to_file(path, result) catch {
        _ => ()
      }
      exit_now(0)
    } else if pid > 0 {
      workers.push((pid, path))
    } else {
      // Fork failed — fall back to sequential for remaining
      all_forked = false
      break
    }
  }
  if !all_forked {
    // Wait for already-forked children
    for w in workers {
      let _ = waitpid_native(w.0)
    }
    // Clean up partial results
    for w in workers {
      let _ = unlink_native(w.1)
    }
    let _ = rmdir_native(dir)
    // Run all tasks sequentially
    let results : Array[String] = []
    for task in tasks {
      results.push(task())
    }
    return results
  }
  // Parent: wait for all children and collect results
  let results : Array[String] = []
  for w in workers {
    let _ = waitpid_native(w.0)
    let data = @fs.read_file_to_string(w.1) catch { _ => "" }
    results.push(data)
    let _ = unlink_native(w.1)
  }
  let _ = rmdir_native(dir)
  results
}
