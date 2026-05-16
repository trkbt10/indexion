/// Identity — names as first-class citizens.
///
/// What this package is for
/// ------------------------
/// "A name is a promise to point at something." Files have names,
/// headings have titles, modules have identifiers, characters have
/// proper nouns. In every case the name and the thing it names are
/// **two different artefacts** that drift apart over time:
///
///   - the writer renames a file but the body still discusses an
///     older subject
///   - a heading is "Setting Notes" but the body is about a single
///     character
///   - a function is called `parse_kgf` but its body now does
///     resolution as well
///
/// Tools that conflate the two — by, say, deriving a slug from the
/// title and using it as the file id — bake the drift in. This
/// package treats names as **identifiers we care about per se** and
/// gives the rest of indexion a vocabulary for talking about them:
///
///   - `Name` is the data type (id role + display role)
///   - `NamedEntity` ties a name to a content body so they can be
///     compared
///   - `NameDivergence` is a reconcile-style report of drift
///   - `derive_name` proposes a name from content using KGF spec
///   - `score_name_divergence` measures how far an existing name has
///     drifted from its body
///
/// What this package is NOT
/// -------------------------
/// It is not a slug helper. URL slugs and anchor IDs have their own
/// well-defined formats handled by `@common.slugify` and
/// `@common.make_anchor`. This package is about the *relationship*
/// between names and content; sluggification is one possible serialised
/// form of an `Id`, not the subject of the package.

///|
/// A name is a pair of two roles played by one or two strings:
///
/// - **id**     — the stable identifier, used to address the entity
///   from other places. Surviving rename pressure is the id's job.
/// - **display** — the human-facing label. Allowed to change with the
///   content; expected to evolve.
///
/// They start out the same when a name is first chosen, and may diverge
/// as the entity matures. We keep both so callers can ask either "is
/// this still the same thing?" (id) or "what would I call it now?"
/// (display).
pub struct Name {
  id : String
  display : String
} derive(ToJson)

///|
pub fn Name::new(id~ : String, display~ : String) -> Name {
  { id, display }
}

///|
/// Construct a name where id and display are the same string. Used
/// for legacy data that has only one form.
pub fn Name::single(value : String) -> Name {
  { id: value, display: value }
}

///|
pub fn Name::get_id(self : Name) -> String {
  self.id
}

///|
pub fn Name::get_display(self : Name) -> String {
  self.display
}

///|
/// A named entity: a body of content that already has a name attached.
/// Reconcile asks "does this name still fit this body?".
pub struct NamedEntity {
  name : Name
  /// The content the name claims to refer to. This is the prose, code,
  /// section body, etc. — not the rendered display string.
  content : String
  /// Where the entity lives. Used as a path hint when tokenising the
  /// content through KGF, so the right spec is selected.
  origin : String
} derive(ToJson)

///|
pub fn NamedEntity::new(
  name~ : Name,
  content~ : String,
  origin~ : String,
) -> NamedEntity {
  { name, content, origin }
}

///|
pub fn NamedEntity::get_name(self : NamedEntity) -> Name {
  self.name
}

///|
pub fn NamedEntity::get_content(self : NamedEntity) -> String {
  self.content
}

///|
pub fn NamedEntity::get_origin(self : NamedEntity) -> String {
  self.origin
}

///|
/// Recommendation for what to do about a name that has drifted from
/// its content.
pub enum NameAction {
  /// Name fits the content; nothing to do.
  Keep
  /// Name doesn't appear in the content prominently; consider rewording
  /// the name to reflect what's actually written.
  Rename
  /// The body covers multiple distinct subjects; the name can no
  /// longer summarise it. Split into separate entities.
  Split
  /// The body has been hollowed out; the name now points at very little
  /// substance. Either grow the body or remove the entity.
  Hollow
} derive(Eq, Debug)

///|
pub fn NameAction::label(self : NameAction) -> String {
  match self {
    Keep => "keep"
    Rename => "rename"
    Split => "split"
    Hollow => "hollow"
  }
}

///|
/// Custom ToJson: emit the kebab-case label so JSON consumers see the
/// same string as the rationale prefix.
pub impl ToJson for NameAction with to_json(self) {
  self.label().to_json()
}

///|
/// One reconcile candidate for a name ↔ content pair.
pub struct NameDivergence {
  /// The entity whose name and content disagree.
  entity : NamedEntity
  /// 0..1: how strongly the name's vocabulary actually appears in the
  /// content. 1 = name is fully present, 0 = name shares no vocabulary
  /// with body. Computed by tokenising both sides through the project
  /// SoT and asking whether name tokens are content-token-set members.
  name_in_content_score : Double
  /// 0..1: how diverse the body is — informally, "how many distinct
  /// concepts does the body cover compared to the name". Used to
  /// distinguish "this body is just off-topic" (low diversity) from
  /// "this body covers too much" (high diversity).
  content_breadth : Double
  /// Top tokens from the body that do NOT appear in the name. These
  /// are candidates for renaming or splitting.
  prominent_unused : Array[String]
  /// Recommended action.
  action : NameAction
  /// One-line human-readable rationale.
  rationale : String
} derive(ToJson)

///|
pub fn NameDivergence::get_entity(self : NameDivergence) -> NamedEntity {
  self.entity
}

///|
pub fn NameDivergence::get_name_in_content_score(
  self : NameDivergence,
) -> Double {
  self.name_in_content_score
}

///|
pub fn NameDivergence::get_content_breadth(self : NameDivergence) -> Double {
  self.content_breadth
}

///|
pub fn NameDivergence::get_prominent_unused(
  self : NameDivergence,
) -> Array[String] {
  self.prominent_unused
}

///|
pub fn NameDivergence::get_action(self : NameDivergence) -> NameAction {
  self.action
}

///|
pub fn NameDivergence::get_rationale(self : NameDivergence) -> String {
  self.rationale
}
