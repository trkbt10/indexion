///|
/// FstAction represents an action to perform during FST state transition.
pub enum FstAction {
  /// Emit the input character to output
  EmitInput
  /// Emit a specific string value to output
  Emit(String)
  /// Buffer the input character for later processing
  Buf
  /// Flush the buffer with specified padding (0, 1, or 2)
  Flush(Int)
}

///|
/// Creates an EmitInput action.
pub fn FstAction::emit_input() -> FstAction {
  EmitInput
}

///|
/// Creates an Emit action with the specified value.
pub fn FstAction::emit(value : String) -> FstAction {
  Emit(value)
}

///|
/// Creates a Buf action.
pub fn FstAction::buf() -> FstAction {
  Buf
}

///|
/// Creates a Flush action with the specified padding.
pub fn FstAction::flush(pad : Int) -> FstAction {
  Flush(pad)
}

///|
/// FstTransition represents a single state transition in the FST.
pub struct FstTransition {
  /// Input class name to match (or "*" for wildcard)
  on : String
  /// Target state name
  to : String
  /// Actions to execute during transition
  actions : Array[FstAction]
}

///|
/// Creates a new FstTransition.
pub fn FstTransition::new(
  on : String,
  to : String,
  actions : Array[FstAction],
) -> FstTransition {
  { on, to, actions }
}

///|
/// Returns the input class to match.
pub fn FstTransition::get_on(self : FstTransition) -> String {
  self.on
}

///|
/// Returns the target state.
pub fn FstTransition::get_to(self : FstTransition) -> String {
  self.to
}

///|
/// Returns the actions to execute.
pub fn FstTransition::get_actions(self : FstTransition) -> Array[FstAction] {
  self.actions
}

///|
/// PreprocessFstSpec represents a JSON-defined preprocess FST specification.
pub struct PreprocessFstSpec {
  /// Name of this FST
  name : String
  /// Character classes: name -> regex pattern
  classes : Map[String, String]
  /// Initial state name
  initial : String
  /// State transitions: state_name -> array of transitions
  states : Map[String, Array[FstTransition]]
}

///|
/// Creates a new PreprocessFstSpec.
pub fn PreprocessFstSpec::new(
  name : String,
  classes : Map[String, String],
  initial : String,
  states : Map[String, Array[FstTransition]],
) -> PreprocessFstSpec {
  { name, classes, initial, states }
}

///|
/// Returns the FST name.
pub fn PreprocessFstSpec::get_name(self : PreprocessFstSpec) -> String {
  self.name
}

///|
/// Returns the character classes.
pub fn PreprocessFstSpec::get_classes(
  self : PreprocessFstSpec,
) -> Map[String, String] {
  self.classes
}

///|
/// Returns the initial state name.
pub fn PreprocessFstSpec::get_initial(self : PreprocessFstSpec) -> String {
  self.initial
}

///|
/// Returns the states.
pub fn PreprocessFstSpec::get_states(
  self : PreprocessFstSpec,
) -> Map[String, Array[FstTransition]] {
  self.states
}
