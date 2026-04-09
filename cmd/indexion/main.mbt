///|
/// # indexion
///
/// Source code exploration and documentation tool.
///
/// ## Overview
///
/// indexion provides tools for analyzing, exploring, and documenting source code.
/// Named after Korzybski's "the map is not the territory" - indexion helps build
/// dynamic maps of your codebase.
///
/// ## Installation
///
/// ```bash
/// # Build from source
/// moon build --target native
///
/// # Or download release
/// # See: https://github.com/trkbt10/indexion/releases
/// ```
///
/// ## Commands
///
/// | Command | Description |
/// |---------|-------------|
/// | `explore` | Analyze file similarity in a directory |
/// | `plan refactor` | Generate refactoring plan from similarity |
/// | `plan documentation` | Analyze documentation coverage |
/// | `plan unwrap` | Detect unnecessary wrapper functions |
/// | `plan solid` | Plan cross-package code extraction |
/// | `plan reconcile` | Detect implementation/documentation drift |
/// | `doc graph` | Generate dependency graph |
/// | `doc readme` | Generate README from source doc comments |
/// | `digest` | Purpose-based function index |
/// | `kgf` | KGF spec management and inspection |
/// | `sim` | Calculate text similarity/distance |
/// | `segment` | Split text into contextual segments |
/// | `search` | Semantic search across code, wiki, and docs |
/// | `grep` | KGF-aware token pattern search |
/// | `perf kgf` | Run KGF parser performance benchmarks |
///
/// ## Quick Start
///
/// ```bash
/// # Explore similarity in your codebase
/// indexion explore --format=list src/
///
/// # Generate refactoring plan
/// indexion plan refactor --threshold=0.8 src/
///
/// # Generate dependency graph
/// indexion doc graph --format=mermaid src/
/// ```
///
/// ## Configuration
///
/// - KGF specs: `kgfs/` directory for language specifications
/// - Doc config: `doc.json` for documentation generation settings

///|
fn build_command() -> @argparse.Command {
  @argparse.Command(
    "indexion",
    about="Source code exploration and documentation tool",
    version=@update.current_version,
    subcommand_required=true,
    subcommands=[
      @init_cli.command(),
      @explore_cli.command(),
      @plan_cli.command(),
      @doc_cli.command(),
      @kgf_cli.command(),
      @digest_cli.command(),
      @similarity_cli.command(),
      @segment_cli.command(),
      @perf_cli.command(),
      @update_cli.command(),
      @serve_cli.command(),
      @grep_cli.command(),
      @search_cli.command(),
      @mcp_cli.command(),
      @spec_cli.command(),
      @wiki_cli.command(),
    ],
  )
}

///|
/// Main entry point.
async fn main {
  let cmd = build_command()
  let matches = cmd.parse() catch {
    err => {
      println(err.to_string())
      return
    }
  }
  guard matches.subcommand is Some((name, sub)) else { return }
  match name {
    "init" => @init_cli.run_matches(sub)
    "explore" => @explore_cli.run_matches(sub)
    "plan" => @plan_cli.dispatch(sub)
    "doc" => @doc_cli.dispatch(sub)
    "kgf" => @kgf_cli.run_matches(sub)
    "digest" => @digest_cli.run_matches(sub)
    "sim" => @similarity_cli.run_matches(sub)
    "segment" => @segment_cli.run_matches(sub)
    "perf" => @perf_cli.dispatch(sub)
    "update" => @update_cli.run_matches(sub)
    "serve" => @serve_cli.run_matches(sub)
    "grep" => @grep_cli.run_matches(sub)
    "search" => @search_cli.run_matches(sub)
    "mcp" => @mcp_cli.run_matches(sub)
    "spec" => @spec_cli.dispatch(sub)
    "wiki" => @wiki_cli.dispatch(sub)
    _ => ()
  }
}
