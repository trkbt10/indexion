///|
/// # indexion doc okf
///
/// Export analyzed knowledge as an Open Knowledge Format (OKF) bundle.
///
/// ## Overview
///
/// OKF (GoogleCloudPlatform/knowledge-catalog) is an open, vendor-neutral
/// format that represents knowledge as a directory of markdown files with
/// YAML frontmatter, so that both humans and AI agents can consume it.
/// This command turns indexion's analyzed knowledge graph — packages,
/// public declarations, and dependency edges — into such a bundle:
///
/// - one concept document per analyzed package (`packages/<path>.md`)
/// - one concept document per external dependency (`dependencies/<path>.md`)
/// - `index.md` listings in every directory for progressive disclosure
/// - a `log.md` generation history at the bundle root
///
/// ## Usage
///
/// ```bash
/// indexion doc okf [options] --output=DIR [paths...]
/// ```
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--output=DIR` | Output directory for the bundle (required) | |
/// | `--specs-dir=DIR` | KGF specs directory | kgfs |
/// | `--include=PATTERN` | Include packages matching glob (repeatable) | all |
/// | `--exclude=PATTERN` | Exclude packages matching glob (repeatable) | none |
/// | `--recursive` | Scan directories recursively | true |
/// | `--title=TITLE` | Bundle title | root directory name |
///
/// ## Examples
///
/// ```bash
/// # Export src/ knowledge as an OKF bundle
/// indexion doc okf --output=okf-bundle src/
///
/// # Export the whole project, excluding tests
/// indexion doc okf --output=okf-bundle --exclude='*_wbtest.mbt' .
/// ```

///|
/// Configuration for OKF bundle export.
pub struct OkfConfig {
  paths : Array[String]
  specs_dirs : Array[String]
  includes : Array[String]
  excludes : Array[String]
  recursive : Bool
  output : String
  title : String
}

///|
/// Create a default OKF export configuration.
pub fn OkfConfig::default() -> OkfConfig {
  {
    paths: [],
    specs_dirs: [],
    includes: [],
    excludes: [],
    recursive: true,
    output: "",
    title: "",
  }
}

///|
/// Create OkfConfig from argparse matches.
pub fn OkfConfig::from_matches(matches : @argparse.Matches) -> OkfConfig {
  let specs_dirs = @common.arg_specs_dirs(matches)
  let includes = matches.values.get("include").unwrap_or([])
  let excludes = matches.values.get("exclude").unwrap_or([])
  let recursive = matches.flags.get("recursive").unwrap_or(true)
  let output = match matches.values.get("output") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let title = match matches.values.get("title") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let paths = match matches.values.get("paths") {
    Some(arr) if arr.length() > 0 => arr
    _ => ["."]
  }
  { paths, specs_dirs, includes, excludes, recursive, output, title, }
}

///|
/// Define the okf command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "okf",
    about="Export analyzed knowledge as an Open Knowledge Format (OKF) bundle",
    options=[
      @argparse.OptionArg(
        "output",
        short='o',
        required=true,
        about="Output directory for the OKF bundle",
      ),
      @help.specs_dir_option(),
      @argparse.OptionArg(
        "include",
        action=Append,
        about="Include packages matching glob (repeatable)",
      ),
      @argparse.OptionArg(
        "exclude",
        action=Append,
        about="Exclude packages matching glob (repeatable)",
      ),
      @argparse.OptionArg(
        "title",
        about="Bundle title (default: analysis root directory name)",
      ),
    ],
    flags=[
      @argparse.FlagArg(
        "recursive",
        negatable=true,
        about="Scan directories recursively (default: true)",
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "paths",
        num_args=@argparse.ValueRange(lower=0),
        about="Paths to scan",
      ),
    ],
  )
}

///|
/// Run the doc okf command from argparse matches.
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = OkfConfig::from_matches(matches)
  // Stage 1: Load KGF specs.
  println("[1/5] Loading KGF specs...")
  let registry = @kgf_features.load_registry_or_empty(
    specs_dirs=config.specs_dirs,
    target_dirs=config.paths,
  )
  if registry.spec_count() > 0 {
    println("      Loaded " + registry.spec_count().to_string() + " specs")
  } else {
    println("Warning: No KGF specs found")
  }
  // Stage 2: Collect candidate files using KGF ignore patterns.
  println("[2/5] Discovering files...")
  let kgf_ignore = registry.collect_ignore_patterns()
  let root_dir = @pipeline.root_dir_from_paths(config.paths)
  let discover_opts = @pipeline.DiscoverOptions::new(
    root_dir~,
    recursive=config.recursive,
    excludes=config.excludes,
    kgf_ignore~,
  )
  let candidate_paths = @pipeline.discover_files(config.paths, discover_opts)
  if candidate_paths.length() == 0 {
    println("No files found.")
    return
  }
  println("      Found " + candidate_paths.length().to_string() + " files")
  // Stage 3: Group files into packages.
  println("[3/5] Grouping packages...")
  let packages = @readme.discover_packages_from_files(
    registry,
    candidate_paths,
    config.includes,
    config.excludes,
  )
  if packages.length() == 0 {
    println("No packages found.")
    return
  }
  println("      Found " + packages.length().to_string() + " packages")
  // Stage 4: Build one knowledge graph across all analyzed files.
  println("[4/5] Building knowledge graph...")
  let supported = @pipeline.load_supported_file_info(candidate_paths, registry)
  let file_contents : Array[(String, String)] = []
  let contents : Map[String, String] = Map([])
  for file in supported {
    file_contents.push((file.path, file.content))
    contents.set(file.path, file.content)
  }
  let specs = registry.to_specs_map()
  let graph = @build.build_graph_only(
    @build.DocConfig::new(file_contents, specs),
  )
  let concepts = assemble_concepts(packages, graph, registry, specs, contents)
  // Stage 5: Render and write the bundle.
  println("[5/5] Writing OKF bundle...")
  let title = if config.title.length() > 0 {
    config.title
  } else {
    default_bundle_title(root_dir)
  }
  let options : @okf_bundle.OkfBundleOptions = {
    title,
    timestamp: @common.now_iso8601_utc(),
  }
  let bundle = @okf_bundle.build_bundle(concepts, options)
  @doc_config.ensure_dir_recursive(config.output)
  let mut written = 0
  for entry in bundle {
    let (rel_path, content) = entry
    let out_path = config.output + "/" + rel_path
    @doc_config.ensure_parent_dir(out_path)
    @fs.write_string_to_file(out_path, content) catch {
      @fs.IOError(msg) => {
        println("  Error writing " + out_path + ": " + msg)
        continue
      }
    }
    written = written + 1
  }
  println(
    "OKF bundle written to: " +
    config.output +
    " (" +
    written.to_string() +
    " files)",
  )
}

///|
/// Derive a bundle title from the analysis root: its directory name, or the
/// project root's directory name when the root is the current directory.
fn default_bundle_title(root_dir : String) -> String {
  let base = @pipeline.extract_basename(root_dir)
  if base != "." && base != "" {
    return base
  }
  match @doc_config.find_project_root_from(root_dir) {
    Some(project_root) => {
      let project_base = @pipeline.extract_basename(project_root)
      if project_base != "." && project_base != "" {
        project_base
      } else {
        base
      }
    }
    None => base
  }
}
