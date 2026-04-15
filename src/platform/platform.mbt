///|
/// Platform detection and OS-level primitives.
/// Pure OS knowledge — no application-specific constants.

///|
/// Detected operating system platform.
pub(all) enum Platform {
  MacOS
  Linux
  Windows
  Unknown
} derive(Eq, Debug)

///|
/// Detect the current operating system platform.
pub fn detect_platform() -> Platform {
  match @osenv_platform.platform() {
    Linux => Linux
    MacOS => MacOS
    Windows => Windows
    Unknown => Unknown
  }
}

///|
/// Get user home directory.
pub fn get_home_dir() -> String? {
  @osenv_dirs.home_dir()
}

///|
fn is_valid_dir_check(path : String) -> Bool {
  @sync_fs.is_dir(path) catch {
    _ => false
  }
}

///|
/// Detected CPU architecture.
pub(all) enum Arch {
  X64
  Arm64
  UnknownArch
} derive(Eq, Debug)

///|
/// Detect the CPU architecture.
/// Windows: PROCESSOR_ARCHITECTURE is authoritative.
/// Unix: HOSTTYPE env var, then probes /usr/lib/aarch64-linux-gnu (Debian/Ubuntu arm64
/// marker) and /usr/lib/x86_64-linux-gnu (x64 marker) as a filesystem heuristic.
pub fn detect_arch() -> Arch {
  // Windows: PROCESSOR_ARCHITECTURE is authoritative
  match @sys.get_env_var("PROCESSOR_ARCHITECTURE") {
    Some(pa) =>
      if pa.length() > 0 {
        if pa == "AMD64" || pa == "x86_64" {
          return X64
        }
        if pa == "ARM64" || pa == "aarch64" {
          return Arm64
        }
      }
    None => ()
  }
  // Unix: HOSTTYPE is set by bash and some other shells
  match @sys.get_env_var("HOSTTYPE") {
    Some(ht) =>
      if ht.length() > 0 {
        if ht.contains("x86_64") || ht.contains("amd64") {
          return X64
        }
        if ht.contains("aarch64") || ht.contains("arm64") {
          return Arm64
        }
      }
    None => ()
  }
  // Filesystem probes: Debian/Ubuntu multiarch directories indicate CPU arch
  if is_valid_dir_check("/usr/lib/aarch64-linux-gnu") {
    return Arm64
  }
  if is_valid_dir_check("/usr/lib/x86_64-linux-gnu") {
    return X64
  }
  // macOS: probe /usr/libexec/rosetta (present on Apple Silicon, even on Intel→none)
  match detect_platform() {
    MacOS =>
      if is_valid_dir_check("/usr/libexec/rosetta") {
        Arm64
      } else {
        // Pre-M1 Intel Mac
        X64
      }
    _ => UnknownArch
  }
}
