///|
fn temp_git_dir(prefix : String) -> String {
  prefix + @env.now().to_string()
}

///|
fn remove_file_if_exists(path : String) -> Unit {
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
async fn current_repo_root() -> String? {
  match @env.current_dir() {
    Some(dir) => {
      let mut current = @config_paths.normalize_path(dir)
      for _ in 0..<64 {
        if is_repo(current) {
          return Some(current)
        }
        let parent = @config_paths.dirname(current)
        if parent == current {
          break
        }
        current = parent
      }
      None
    }
    None => None
  }
}

///|
async test "vcs/git: native helpers resolve the current repository" {
  guard current_repo_root() is Some(root)
  assert_true(is_repo(root))
  assert_true(last_commit_seconds(root, "moon.mod.json") is Some(_))
}

///|
async test "vcs/git: native helpers do not interpret root shell payloads" {
  guard current_repo_root() is Some(root)
  let marker = temp_git_dir(".indexion/vcs-git-shell-root-marker-")
  remove_file_if_exists(marker)
  let injected_root = root + "; touch " + marker
  assert_true(not(is_repo(injected_root)))
  assert_true(not(@fs.path_exists(marker)))
  remove_file_if_exists(marker)
}

///|
async test "vcs/git: native helpers do not interpret path shell payloads" {
  guard current_repo_root() is Some(root)
  let marker = temp_git_dir(".indexion/vcs-git-shell-path-marker-")
  remove_file_if_exists(marker)
  let payloads = [
    "moon.mod.json; touch " + marker,
    "moon.mod.json $(touch " + marker + ")",
    "moon.mod.json `touch " + marker + "`",
    "moon.mod.json & touch " + marker,
    "moon.mod.json ' touch " + marker,
    "moon.mod.json \" touch " + marker,
    "moon.mod.json\n touch " + marker,
  ]
  for payload in payloads {
    assert_eq(last_commit_seconds(root, payload), None)
    assert_true(not(status_dirty(root, payload)))
    assert_true(not(@fs.path_exists(marker)))
  }
  remove_file_if_exists(marker)
}
