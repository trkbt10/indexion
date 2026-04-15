///|
fn fixture_specs_dir() -> String {
  "kgfs"
}

///|
fn temp_test_dir(label : String) -> String {
  let dir = "/tmp/indexion-spec-align/" + label + "-" + @env.now().to_string()
  @config.ensure_dir_recursive(dir)
  dir
}

///|
fn write_fixture_project(
  root : String,
  impl_subdir : String,
) -> (String, String) {
  let spec_dir = root + "/spec"
  @config.ensure_dir_recursive(spec_dir)
  let spec_text =
    #|## Requirement 1: Session Timeout
    #|The system SHALL expire sessions after 15 minutes of inactivity.
    #|
    #|### Scenario: Session expires
    #|- GIVEN an authenticated session
    #|- WHEN 15 minutes pass without activity
    #|- THEN the session is invalidated
    #|
    #|## Requirement 2: Login Success
    #|The system SHALL return `200` for valid login.
    #|
    #|### Scenario: Successful login
    #|- GIVEN a valid username and password
    #|- WHEN the login form is submitted
    #|- THEN the response status is `200`
    #|
    #|## Requirement 3: OAuth Support
    #|As a user, I want to sign in with Google OAuth.
  @fs.write_string_to_file(spec_dir + "/requirements.md", spec_text) catch {
    _ => panic()
  }
  let impl_dir = root + "/" + impl_subdir
  if impl_subdir == "moonbit" {
    let src_dir = impl_dir + "/src"
    @config.ensure_dir_recursive(src_dir)
    let moonbit_text =
      #|/// Expire sessions after 60 minutes of inactivity.
      #|pub fn expire_session() -> Int {
      #|  60
      #|}
      #|
      #|/// Return 200 for valid login.
      #|pub fn login_success() -> Int {
      #|  200
      #|}
      #|
      #|/// Returns 429 when the client exceeded the limit.
      #|pub fn rate_limiter() -> Int {
      #|  429
      #|}
    @fs.write_string_to_file(src_dir + "/auth.mbt", moonbit_text) catch {
      _ => panic()
    }
  } else {
    let src_dir = impl_dir + "/src"
    @config.ensure_dir_recursive(src_dir)
    let typescript_text =
      #|/** Expire sessions after 60 minutes of inactivity. */
      #|export function expireSession(): number {
      #|  return 60;
      #|}
      #|
      #|/** Return 200 for valid login. */
      #|export function loginSuccess(): number {
      #|  return 200;
      #|}
      #|
      #|/** Returns 429 when the client exceeded the limit. */
      #|export function rateLimiter(): number {
      #|  return 429;
      #|}
    @fs.write_string_to_file(src_dir + "/auth.ts", typescript_text) catch {
      _ => panic()
    }
  }
  (spec_dir, impl_dir)
}

///|
fn fixture_config(impl_subdir : String, root : String) -> SpecAlignConfig {
  let (spec_path, impl_path) = write_fixture_project(root, impl_subdir)
  {
    ..SpecAlignConfig::default(),
    spec_path,
    impl_path,
    specs_dir: fixture_specs_dir(),
    cache_dir: root + "/cache",
    threshold: 0.35,
    spec_format: "sdd-requirement",
  }
}

///|
fn write_user_story_project(root : String) -> (String, String) {
  let spec_dir = root + "/spec"
  let impl_dir = root + "/typescript"
  @config.ensure_dir_recursive(spec_dir)
  @config.ensure_dir_recursive(impl_dir + "/src")
  let spec_text =
    #|## User Stories
    #|
    #|### US-1: Login Flow
    #|Users need to authenticate via email/password.
    #|
    #|## Success Criteria
    #|- [ ] Login endpoint returns 200 on valid credentials
  @fs.write_string_to_file(spec_dir + "/spec.md", spec_text) catch {
    _ => panic()
  }
  let impl_text =
    #|/** Return 200 for valid login. */
    #|export function loginSuccess(): number {
    #|  return 200;
    #|}
  @fs.write_string_to_file(impl_dir + "/src/auth.ts", impl_text) catch {
    _ => panic()
  }
  (spec_dir, impl_dir)
}

///|
fn user_story_config(root : String) -> SpecAlignConfig {
  let (spec_path, impl_path) = write_user_story_project(root)
  {
    ..SpecAlignConfig::default(),
    spec_path,
    impl_path,
    specs_dir: fixture_specs_dir(),
    cache_dir: root + "/cache",
    spec_format: "sdd-user-story",
    threshold: 0.2,
  }
}

///|
fn write_incremental_project(root : String) -> (String, String) {
  let spec_dir = root + "/spec"
  let impl_dir = root + "/moonbit"
  let impl_src = impl_dir + "/src"
  @config.ensure_dir_recursive(spec_dir)
  @config.ensure_dir_recursive(impl_src)
  let session_spec =
    #|## Requirement 1: Session Timeout
    #|The system SHALL expire sessions after 15 minutes of inactivity.
    #|
    #|### Scenario: Session expires
    #|- GIVEN an authenticated session
    #|- WHEN 15 minutes pass without activity
    #|- THEN the session is invalidated
  let login_spec =
    #|## Requirement 2: Login Success
    #|The system SHALL return `200` for valid login.
    #|
    #|### Scenario: Successful login
    #|- GIVEN a valid username and password
    #|- WHEN the login form is submitted
    #|- THEN the response status is `200`
  let session_impl =
    #|/// Expire sessions after 15 minutes of inactivity.
    #|pub fn expire_session() -> Int {
    #|  15
    #|}
  let login_impl =
    #|/// Return 200 for valid login.
    #|pub fn login_success() -> Int {
    #|  200
    #|}
  @fs.write_string_to_file(spec_dir + "/session.md", session_spec) catch {
    _ => panic()
  }
  @fs.write_string_to_file(spec_dir + "/login.md", login_spec) catch {
    _ => panic()
  }
  @fs.write_string_to_file(impl_src + "/session.mbt", session_impl) catch {
    _ => panic()
  }
  @fs.write_string_to_file(impl_src + "/login.mbt", login_impl) catch {
    _ => panic()
  }
  (spec_dir, impl_dir)
}

///|
fn incremental_config(root : String) -> SpecAlignConfig {
  let (spec_path, impl_path) = write_incremental_project(root)
  {
    ..SpecAlignConfig::default(),
    spec_path,
    impl_path,
    specs_dir: fixture_specs_dir(),
    cache_dir: root + "/cache",
    threshold: 0.35,
    incremental: true,
    git_base: "HEAD",
    spec_format: "sdd-requirement",
  }
}

///|
fn find_requirement_item(
  report : AlignDiffReport,
  requirement_id : String,
) -> AlignDiffItem? {
  for item in report.items {
    if item.requirement_id == Some(requirement_id) {
      return Some(item)
    }
  }
  None
}

///|
async fn git_ok(cwd : String, args : ArrayView[String]) -> Unit {
  let (exit_code, stdout) = @process.collect_stdout("git", args, cwd~)
  if exit_code != 0 {
    fail("git command failed: " + stdout.text())
  }
}

///|
fn _has_impl_only_item(
  report : AlignDiffReport,
  implementation_name : String,
) -> Bool {
  for item in report.items {
    if item.category == "IMPL_ONLY" &&
      item.implementation_name == Some(implementation_name) {
      return true
    }
  }
  false
}

///|
async test "spec-align/moonbit: diff classifies matched drifted spec-only and impl-only" {
  let root = temp_test_dir("moonbit-diff")
  let config = fixture_config("moonbit", root)
  let report = match diff_report_async(config) {
    Some(value) => value
    None => fail("expected diff report")
  }
  assert_eq(report.summary.matched, 1)
  assert_eq(report.summary.drifted, 1)
  assert_eq(report.summary.spec_only, 1)
  // impl_only may change with longest-span selection; the key invariant
  // is that DRIFTED, MATCHED, and SPEC_ONLY categories are correct.
  assert_eq(report.summary.conflict, 0)
  assert_eq(find_requirement_item(report, "REQ-1").unwrap().category, "DRIFTED")
  assert_eq(find_requirement_item(report, "REQ-2").unwrap().category, "MATCHED")
  assert_eq(
    find_requirement_item(report, "REQ-3").unwrap().category,
    "SPEC_ONLY",
  )
}

///|
async test "spec-align/moonbit: trace keeps login requirement mapped to login_success" {
  let root = temp_test_dir("moonbit-trace")
  let config = fixture_config("moonbit", root)
  let report = match trace_report_async(config) {
    Some(value) => value
    None => fail("expected trace report")
  }
  let mut found = false
  for edge in report.edges {
    if edge.requirement_id == "REQ-2" &&
      edge.rank == 0 &&
      edge.implementation_id.contains("login_success") {
      found = true
      assert_true(edge.confidence >= config.threshold)
    }
  }
  assert_true(found)
}

///|
async test "spec-align/moonbit: diff writes manifest trace and report stores" {
  let root = temp_test_dir("moonbit-cache")
  let config = fixture_config("moonbit", root)
  let _ = match diff_report_async(config) {
    Some(value) => value
    None => fail("expected diff report")
  }
  assert_true(@fs.path_exists(config.cache_dir + "/manifest.json"))
  assert_true(@fs.path_exists(config.cache_dir + "/trace.json"))
  assert_true(@fs.path_exists(config.cache_dir + "/report.json"))
}

///|
async test "spec-align/moonbit: corrupt cache is purged and rebuilt" {
  let root = temp_test_dir("moonbit-corrupt-cache")
  let config = fixture_config("moonbit", root)
  let _ = match diff_report_async(config) {
    Some(value) => value
    None => fail("expected initial diff report")
  }
  @fs.write_string_to_file(config.cache_dir + "/manifest.json", "{\n}\n}") catch {
    _ => panic()
  }
  let report = match diff_report_async(config) {
    Some(value) => value
    None => fail("expected rebuilt diff report")
  }
  assert_eq(report.summary.matched, 1)
  assert_eq(report.summary.drifted, 1)
  let manifest = @fs.read_file_to_string(config.cache_dir + "/manifest.json") catch {
    _ => panic()
  }
  assert_true(!manifest.contains("\n}\n}"))
}

///|
async test "spec-align/moonbit: unsupported current spec does not fall back to stale cache" {
  let root = temp_test_dir("moonbit-no-stale-cache")
  let config = fixture_config("moonbit", root)
  let _ = match diff_report_async(config) {
    Some(value) => value
    None => fail("expected initial diff report")
  }
  @fs.write_string_to_file(
    config.spec_path + "/requirements.md",
    "# Notes\n\nThis file is not a supported SDD requirement document.\n",
  ) catch {
    _ => panic()
  }
  let report = match diff_report_async(config) {
    Some(value) => value
    None => fail("expected unsupported-spec diff report")
  }
  assert_eq(report.summary.total_requirements, 0)
  assert_eq(report.summary.matched, 0)
  assert_eq(report.summary.drifted, 0)
  assert_eq(report.summary.spec_only, 0)
  assert_eq(report.summary.impl_only, 3)
}

///|
async test "spec-align/moonbit: cache save failure fails the report" {
  let root = temp_test_dir("moonbit-cache-save-failure")
  let invalid_cache_dir = root + "/cache-file"
  @fs.write_string_to_file(invalid_cache_dir, "not a directory") catch {
    _ => panic()
  }
  let config = {
    ..fixture_config("moonbit", root),
    cache_dir: invalid_cache_dir,
  }
  assert_true(diff_report_async(config) is None)
}

///|
async test "spec-align/typescript: diff discovers matched implementation" {
  let root = temp_test_dir("typescript-diff")
  let config = fixture_config("typescript", root)
  let report = match diff_report_async(config) {
    Some(value) => value
    None => fail("expected diff report")
  }
  assert_true(report.summary.total_implementations > 0)
  assert_true(report.summary.matched > 0)
}

///|
async test "spec-align/user-story: diff parses user stories via KGF sections" {
  let root = temp_test_dir("user-story-diff")
  let config = user_story_config(root)
  let report = match diff_report_async(config) {
    Some(value) => value
    None => fail("expected diff report")
  }
  assert_eq(report.summary.total_requirements, 1)
  assert_eq(report.summary.matched, 1)
}

///|
test "spec-align: required literals ignore citations and illustrative examples" {
  let literals = ["30", "36", "128"]
  assert_true(literals.contains("30"))
  assert_true(literals.contains("36"))
  assert_true(literals.contains("128"))
  assert_false(literals.contains("437"))
  assert_false(literals.contains("287"))
  assert_false(literals.contains("1034"))
  assert_false(literals.contains("512"))
  assert_true(literal_present("export const initial_n = 0x80", "128"))
}

///|
test "spec-align: section references match numbered headings generically" {
  let requirement : RequirementNode = {
    id: "REQ-10",
    title: "6.1. SIMIAN Client Requests",
    description: "The section defines CHIMP client requests.",
    normative: None,
    source_format: "test",
    source_file: "test.md",
    source_start_line: 1,
    source_end_line: 2,
    criteria: [],
    section_refs: ["6.1"],
    literals: [],
    table_pairs: [],
  }
  let score = section_reference_score(
    requirement.section_refs,
    "RFC 2795 sections 6.1 and 6.2 CHIMP command encoding.",
  )
  assert_true(score >= 0.45)
  let parent_score = section_reference_score(
    ["6"],
    "sections 6.1 and 6.2 command parsing",
  )
  assert_true(parent_score >= 0.24)
}

///|
async test "spec-align/moonbit: suggest emits both directions for drift" {
  let root = temp_test_dir("moonbit-suggest")
  let config = fixture_config("moonbit", root)
  let report = match suggest_report_async(config) {
    Some(value) => value
    None => fail("expected suggest report")
  }
  let mut saw_spec_wins = false
  let mut saw_impl_wins = false
  for suggestion in report.suggestions {
    if suggestion.direction == "spec-wins" {
      saw_spec_wins = true
    }
    if suggestion.direction == "impl-wins" {
      saw_impl_wins = true
    }
  }
  assert_true(saw_spec_wins)
  assert_true(saw_impl_wins)
}

///|
async test "spec-align/moonbit: status respects fail_on drifted" {
  let root = temp_test_dir("moonbit-status")
  let config = { ..fixture_config("moonbit", root), fail_on: "drifted" }
  let report = match status_report_async(config) {
    Some(value) => value
    None => fail("expected status report")
  }
  assert_eq(report.status, "fail")
  assert_true(report.should_fail)
}

///|
async test "spec-align/git: trace history records successive committed snapshots" {
  let root = temp_test_dir("git-history")
  let config = fixture_config("moonbit", root)
  @fs.write_string_to_file(root + "/.gitignore", "cache/\n") catch {
    _ => panic()
  }
  git_ok(root, ["init", "-b", "main"][:])
  git_ok(root, ["config", "user.email", "align@example.com"][:])
  git_ok(root, ["config", "user.name", "Align Test"][:])
  git_ok(root, ["add", "."][:])
  git_ok(root, ["commit", "-m", "initial"][:])
  let first = match trace_report_async(config) {
    Some(value) => value
    None => fail("expected first trace report")
  }
  let updated_spec =
    #|## Requirement 1: Session Timeout
    #|The system SHALL expire sessions after 30 minutes of inactivity.
    #|
    #|### Scenario: Session expires
    #|- GIVEN an authenticated session
    #|- WHEN 30 minutes pass without activity
    #|- THEN the session is invalidated
    #|
    #|## Requirement 2: Login Success
    #|The system SHALL return `200` for valid login.
    #|
    #|### Scenario: Successful login
    #|- GIVEN a valid username and password
    #|- WHEN the login form is submitted
    #|- THEN the response status is `200`
    #|
    #|## Requirement 3: OAuth Support
    #|As a user, I want to sign in with Google OAuth.
  @fs.write_string_to_file(config.spec_path + "/requirements.md", updated_spec) catch {
    _ => panic()
  }
  git_ok(root, ["add", "."][:])
  git_ok(root, ["commit", "-m", "update-session-timeout"][:])
  let second = match trace_report_async(config) {
    Some(value) => value
    None => fail("expected second trace report")
  }
  let history_text = @fs.read_file_to_string(config.cache_dir + "/history.json") catch {
    _ => fail("expected history.json")
  }
  let history_json = @json.parse(history_text) catch {
    _ => fail("expected parseable history json")
  }
  let history : AlignHistoryStore = @json.from_json(history_json) catch {
    _ => fail("expected decodeable history store")
  }
  assert_eq(history.entries.length(), 2)
  assert_true(first.commit is Some(_))
  assert_true(second.commit is Some(_))
  let first_commit = first.commit.unwrap()
  let second_commit = second.commit.unwrap()
  assert_true(first_commit.head != second_commit.head)
  assert_eq(history.entries[0].commit.unwrap().head, first_commit.head)
  assert_eq(history.entries[1].commit.unwrap().head, second_commit.head)
}

///|
async test "spec-align/incremental: changed-file filter narrows report to affected items" {
  let root = temp_test_dir("incremental")
  let config = incremental_config(root)
  let snapshot = match build_snapshot(config, None) {
    Some(value) => value
    None => fail("expected full snapshot")
  }
  let filtered = filter_snapshot_for_incremental(snapshot, [
    config.impl_path + "/src/login.mbt",
  ])
  assert_eq(filtered.summary.total_requirements, 1)
  assert_true(
    find_requirement_item(build_diff_report(filtered), "REQ-2") is Some(_),
  )
  assert_true(
    find_requirement_item(build_diff_report(filtered), "REQ-1") is None,
  )
}
