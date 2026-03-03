///|
/// ScopeEntry represents a single scope frame with value and type namespaces.
pub struct ScopeEntry {
  value_ns : Map[String, String]
  type_ns : Map[String, String]
}

///|
/// Creates a new empty ScopeEntry.
pub fn ScopeEntry::new() -> ScopeEntry {
  { value_ns: {}, type_ns: {} }
}

///|
/// Gets a value from the value namespace.
pub fn ScopeEntry::get_value(self : ScopeEntry, name : String) -> String? {
  self.value_ns.get(name)
}

///|
/// Gets a value from the type namespace.
pub fn ScopeEntry::get_type(self : ScopeEntry, name : String) -> String? {
  self.type_ns.get(name)
}

///|
/// Sets a value in the value namespace.
pub fn ScopeEntry::set_value(
  self : ScopeEntry,
  name : String,
  value : String,
) -> Unit {
  self.value_ns.set(name, value)
}

///|
/// Sets a value in the type namespace.
pub fn ScopeEntry::set_type(
  self : ScopeEntry,
  name : String,
  value : String,
) -> Unit {
  self.type_ns.set(name, value)
}

///|
/// Env represents the evaluation environment with PEG labels and local variables.
pub struct Env {
  labels : Map[String, Json]
  locals : Map[String, Json]
}

///|
/// Creates a new Env with the specified labels.
pub fn Env::new(labels : Map[String, Json]) -> Env {
  { labels, locals: {} }
}

///|
/// Gets a value from locals or labels by name.
pub fn Env::get(self : Env, name : String) -> Json? {
  match self.locals.get(name) {
    Some(v) => Some(v)
    None => self.labels.get(name)
  }
}

///|
/// Sets a local variable.
pub fn Env::set_local(self : Env, name : String, value : Json) -> Unit {
  self.locals.set(name, value)
}

///|
/// SemEvalCtx represents the evaluation context for semantics processing.
/// Note: file_exists is a function that checks if a file exists at the given path.
pub struct SemEvalCtx {
  spec : @types.KGFSpec
  graph : @graph.CodeGraph
  file : String
  root : String
  language : String
  scopes : Array[ScopeEntry]
  sym_seq : Ref[Int]
  call_seq : Ref[Int]
  call_stack : Array[String]
  events : Array[(String, Map[String, Json])]
  file_exists : (String) -> Bool
}

///|
/// Creates a new SemEvalCtx with the specified parameters.
pub fn SemEvalCtx::new(
  spec : @types.KGFSpec,
  graph : @graph.CodeGraph,
  file : String,
  root : String,
  language : String,
  file_exists : (String) -> Bool,
) -> SemEvalCtx {
  {
    spec,
    graph,
    file,
    root,
    language,
    scopes: [ScopeEntry::new()],
    sym_seq: Ref::new(0),
    call_seq: Ref::new(0),
    call_stack: [],
    events: [],
    file_exists,
  }
}

///|
/// Pushes a new scope onto the scope stack.
pub fn SemEvalCtx::push_scope(self : SemEvalCtx) -> Unit {
  self.scopes.push(ScopeEntry::new())
}

///|
/// Pops the top scope from the scope stack.
pub fn SemEvalCtx::pop_scope(self : SemEvalCtx) -> Unit {
  if self.scopes.length() > 1 {
    let _ = self.scopes.pop()
  }
}

///|
/// Gets the current (top) scope.
pub fn SemEvalCtx::current_scope(self : SemEvalCtx) -> ScopeEntry {
  self.scopes[self.scopes.length() - 1]
}

///|
/// Looks up a name in the scope stack (searches from top to bottom).
pub fn SemEvalCtx::lookup_scope(
  self : SemEvalCtx,
  ns : String,
  name : String,
) -> String? {
  for i = self.scopes.length() - 1; i >= 0; i = i - 1 {
    let scope = self.scopes[i]
    let result = if ns == "type" {
      scope.get_type(name)
    } else {
      scope.get_value(name)
    }
    match result {
      Some(v) => return Some(v)
      None => continue
    }
  }
  None
}

///|
/// Gets the current call ID from the call stack.
pub fn SemEvalCtx::current_call_id(self : SemEvalCtx) -> String? {
  if self.call_stack.length() > 0 {
    Some(self.call_stack[self.call_stack.length() - 1])
  } else {
    None
  }
}

///|
/// Generates the next auto symbol ID.
pub fn SemEvalCtx::next_sym_id(self : SemEvalCtx) -> String {
  self.sym_seq.val = self.sym_seq.val + 1
  self.sym_seq.val.to_string()
}

///|
/// Generates the next auto call ID.
pub fn SemEvalCtx::next_call_id(self : SemEvalCtx) -> String {
  self.call_seq.val = self.call_seq.val + 1
  self.call_seq.val.to_string()
}

///|
/// Adds an event to the events list.
pub fn SemEvalCtx::add_event(
  self : SemEvalCtx,
  event_type : String,
  payload : Map[String, Json],
) -> Unit {
  self.events.push((event_type, payload))
}

///|
/// Collects and removes all Ref events from the events list.
pub fn SemEvalCtx::collect_refs(self : SemEvalCtx) -> Array[Map[String, Json]] {
  let refs : Array[Map[String, Json]] = []
  let remaining : Array[(String, Map[String, Json])] = []
  for event in self.events {
    if event.0 == "Ref" {
      refs.push(event.1)
    } else {
      remaining.push(event)
    }
  }
  // Clear and repopulate events array
  while self.events.length() > 0 {
    let _ = self.events.pop()
  }
  for e in remaining {
    self.events.push(e)
  }
  refs
}
