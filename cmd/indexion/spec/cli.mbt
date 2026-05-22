///|
/// Spec CLI - Specification-driven analysis.
/// Subcommands:
///   draft  - Generate an SDD draft from usage/readme documents
///   verify     - Check spec-to-implementation conformance
///   vocabulary - Check KGF-backed vocabulary coverage/drift
///   align      - Align SDD-style specs and implementation

///|
/// Build the argparse Command for the spec subcommand.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "spec",
    about="Specification-driven analysis (verify conformance, etc.)",
    subcommand_required=true,
    subcommands=[
      @draft.command(),
      @verify.command(),
      @align.command(),
      @vocabulary.command(),
    ],
  )
}

///|
/// Dispatch spec subcommand based on parsed matches.
pub async fn dispatch(matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "draft" => @draft.run_matches(sub)
    "align" => @align.run_matches(sub)
    "verify" => @verify.run_matches(sub)
    "vocabulary" => @vocabulary.run_matches(sub)
    _ => ()
  }
}
