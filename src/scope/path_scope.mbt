///|
/// A path matching subject with canonical and alternate path spellings.
pub struct PathSubject {
  candidate_paths : Array[String]
} derive(Eq, Show)

///|
pub fn PathSubject::new(
  path : String,
  additional_paths? : Array[String] = [],
) -> PathSubject {
  let candidate_paths : Array[String] = []
  fn push_unique(candidate_paths : Array[String], path : String) -> Unit {
    if path.length() == 0 {
      return
    }
    if not(candidate_paths.iter().any(fn(existing) { existing == path })) {
      candidate_paths.push(path)
    }
  }
  push_unique(candidate_paths, path)
  for candidate in additional_paths {
    push_unique(candidate_paths, candidate)
  }
  { candidate_paths, }
}

///|
/// Common path scope matching for command-level selectors.
pub struct PathScope {
  includes : Array[String]
  excludes : Array[String]
} derive(Eq, Show)

///|
pub fn PathScope::new(
  includes? : Array[String] = [],
  excludes? : Array[String] = [],
) -> PathScope {
  { includes, excludes }
}

///|
pub fn PathScope::is_empty(self : PathScope) -> Bool {
  self.includes.is_empty() && self.excludes.is_empty()
}

///|
/// Match a single path against a single glob pattern.
pub fn path_matches_pattern(path : String, pattern : String) -> Bool {
  @glob.glob_match(path, pattern)
}

///|
/// Check whether a subject matches a single scope pattern.
pub fn subject_matches_pattern(subject : PathSubject, pattern : String) -> Bool {
  subject.candidate_paths
  .iter()
  .any(fn(path) { path_matches_pattern(path, pattern) })
}

///|
/// Check whether a single path is included by the scope.
pub fn PathScope::matches_path(self : PathScope, path : String) -> Bool {
  self.matches(PathSubject::new(path))
}

///|
/// Check whether a path subject is included by the scope.
pub fn PathScope::matches(self : PathScope, subject : PathSubject) -> Bool {
  let included = if self.includes.is_empty() {
    true
  } else {
    self.includes
    .iter()
    .any(fn(pattern) { subject_matches_pattern(subject, pattern) })
  }
  if not(included) {
    return false
  }
  not(
    self.excludes
    .iter()
    .any(fn(pattern) { subject_matches_pattern(subject, pattern) }),
  )
}
