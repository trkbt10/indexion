///|
/// # VCS — Version Control System abstraction
///
/// Single Source of Truth for VCS detection and hooks directory resolution.
/// New VCS backends (jj, hg, svn, …) are added here by extending the `VCS` enum
/// and the two lookup tables below. No callers need to change.

///|
/// Supported version control systems.
pub(all) enum VCS {
  Git
  Jujutsu
} derive(Eq, Debug)

///|
/// Filesystem markers that identify a VCS repository root.
/// Order within each entry does not matter; the first matching entry wins
/// when scanning ancestor directories.
let vcs_root_markers : Array[(VCS, Array[String])] = [
  (Git, [".git"]),
  (Jujutsu, [".jj"]),
]

///|
/// The hooks subdirectory relative to the VCS root, per VCS.
/// For Git:     <root>/.git/hooks/
/// For Jujutsu: <root>/.jj/repo/hooks/
let vcs_hooks_subdirs : Array[(VCS, String)] = [
  (Git, ".git/hooks"),
  (Jujutsu, ".jj/repo/hooks"),
]

///|
/// Detect which VCS controls `start_dir` by walking up to the filesystem root.
/// Returns the detected VCS and its repository root, or None.
pub fn detect(start_dir : String) -> (VCS, String)? {
  let normalized = @config_paths.normalize_path(start_dir)
  let mut current = normalized
  while true {
    for entry in vcs_root_markers {
      let (vcs, markers) = entry
      for marker in markers {
        if @fs.path_exists(@config_paths.join_path(current, marker)) {
          return Some((vcs, current))
        }
      }
    }
    let parent = @config_paths.dirname(current)
    if parent == current {
      break
    }
    current = parent
  }
  None
}

///|
/// Return the hooks directory for a known VCS root.
pub fn hooks_dir(vcs : VCS, root : String) -> String {
  for entry in vcs_hooks_subdirs {
    let (v, sub) = entry
    if v == vcs {
      return @config_paths.join_path(root, sub)
    }
  }
  // Fallback: should never happen if vcs_hooks_subdirs is kept in sync with VCS enum.
  @config_paths.join_path(root, ".hooks")
}
