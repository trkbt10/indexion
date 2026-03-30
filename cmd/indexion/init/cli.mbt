///|
/// # indexion init
///
/// Initialize indexion configuration for a project or globally.
///
/// ## Usage
///
/// ```bash
/// indexion init [options] [directory]
/// indexion init --global
/// ```

///|
/// Configuration for init command.
pub struct InitConfig {
  target_dir : String
  is_global : Bool
  force : Bool
}

///|
/// Create a default InitConfig with current directory as target.
pub fn InitConfig::default() -> InitConfig {
  { target_dir: ".", is_global: false, force: false }
}

///|
/// Create InitConfig from argparse Matches.
pub fn InitConfig::from_matches(matches : @argparse.Matches) -> InitConfig {
  let mut config = InitConfig::default()
  match matches.flags.get("global") {
    Some(true) => config = { ..config, is_global: true }
    _ => ()
  }
  match matches.flags.get("force") {
    Some(true) => config = { ..config, force: true }
    _ => ()
  }
  match matches.values.get("directory") {
    Some(dirs) =>
      if dirs.length() > 0 {
        config = { ..config, target_dir: dirs[0] }
      }
    None => ()
  }
  config
}

///|
/// Define the init command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "init",
    about="Initialize indexion configuration",
    flags=[
      @argparse.FlagArg(
        "global",
        short='g',
        about="Initialize global configuration",
      ),
      @argparse.FlagArg("force", short='f', about="Overwrite existing files"),
    ],
    positionals=[
      @argparse.PositionArg(
        "directory",
        about="Target directory (default: current directory)",
        num_args=@argparse.ValueRange(lower=0, upper=1),
      ),
    ],
  )
}

///|
/// Entry point for the init subcommand using argparse Matches.
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = InitConfig::from_matches(matches)
  if config.is_global {
    run_global_init(config.force)
  } else {
    run_project_init(config.target_dir, config.force)
  }
}

///|
fn run_global_init(force : Bool) -> Unit {
  let config_dir = match @config.get_global_config_dir() {
    Some(dir) => dir
    None => {
      println("Error: Cannot determine global config directory")
      return
    }
  }
  let data_dir = match @config.get_global_data_dir() {
    Some(dir) => dir
    None => {
      println("Error: Cannot determine global data directory")
      return
    }
  }
  // Create config directory only (not kgfs - user creates when needed)
  @config.ensure_dir_recursive(config_dir)
  // Create config.toml
  let config_path = @config.join_path(config_dir, "config.toml")
  let kgfs_dir = @config.get_kgfs_install_dir().unwrap_or(
    @config.join_path(data_dir, "kgfs"),
  )
  let files_created : Array[String] = []
  if write_file_if_ok(config_path, generate_global_config_template(), force) {
    files_created.push(config_path)
  }
  // Summary
  if files_created.length() > 0 {
    println("Global configuration initialized:")
    for path in files_created {
      println("  " + path)
    }
    println("")
    println("Next steps:")
    println("  - Edit " + config_path + " to set defaults")
    println(
      "  - To use global KGF specs, create " + kgfs_dir + " and copy spec files",
    )
  } else {
    println("No files created. Use --force to overwrite existing files.")
    println("")
    println("Existing files:")
    println("  " + config_path)
  }
}

///|
fn run_project_init(target_dir : String, force : Bool) -> Unit {
  let normalized = @config.normalize_path(target_dir)
  // Create .indexion directory structure
  let indexion_dir = @config.join_path(normalized, ".indexion")
  let cache_dir = @config.join_path(indexion_dir, "cache")
  let state_dir = @config.join_path(indexion_dir, "state")
  let local_dir = @config.join_path(indexion_dir, "local")
  @config.ensure_dir_recursive(cache_dir)
  @config.ensure_dir_recursive(state_dir)
  @config.ensure_dir_recursive(local_dir)
  // Create .indexion.toml
  let config_path = @config.join_path(normalized, ".indexion.toml")
  let files_created : Array[String] = []
  if write_file_if_ok(config_path, generate_project_config_template(), force) {
    files_created.push(config_path)
  }
  // Create .gitignore in .indexion
  let gitignore_path = @config.join_path(indexion_dir, ".gitignore")
  if write_file_if_ok(gitignore_path, generate_gitignore(), force) {
    files_created.push(gitignore_path)
  }
  // Summary
  if files_created.length() > 0 {
    println("Project initialized:")
    for path in files_created {
      println("  " + path)
    }
    println("")
    println("Directories created:")
    println("  " + cache_dir)
    println("  " + state_dir)
    println("  " + local_dir)
    println("")
    println("Next steps:")
    println("  - Edit .indexion.toml to configure indexion")
    println("  - Run 'indexion plan reconcile' to check documentation drift")
  } else {
    println("No files created. Use --force to overwrite existing files.")
    println("")
    println("Existing files:")
    println("  " + config_path)
  }
}

///|
fn write_file_if_ok(path : String, content : String, force : Bool) -> Bool {
  if not(force) {
    if @fs.path_exists(path) {
      return false
    }
  }
  @fs.write_string_to_file(path, content) catch {
    _ => return false
  }
  true
}

///|
/// Write [digest] configuration section to a buffer.
fn write_digest_section(buf : StringBuilder) -> Unit {
  buf.write_string("[digest]\n")
  buf.write_string("# provider = \"auto\"       # auto | tfidf | openai\n")
  buf.write_string("# strategy = \"hnsw\"       # hnsw | bruteforce | ivf\n")
  buf.write_string("# dim = 256              # TF-IDF dimension (ignored for openai)\n")
  buf.write_string("# api_key_env = \"OPENAI_API_KEY\"  # env var name for API key\n")
  buf.write_string("# api_base_url = \"https://api.openai.com/v1/embeddings\"\n")
  buf.write_string("# model = \"text-embedding-3-small\"\n")
}

///|
/// Write shared reconcile configuration sections to a buffer.
fn write_reconcile_sections(buf : StringBuilder) -> Unit {
  buf.write_string("[reconcile.time]\n")
  buf.write_string("# git_preferred = true\n")
  buf.write_string("# mtime_fallback = true\n")
  buf.write_string("\n")
  buf.write_string("[reconcile.mapping]\n")
  buf.write_string("# allow_file_fallback = true\n")
  buf.write_string("\n")
  buf.write_string("[reconcile.output]\n")
  buf.write_string("# default_format = \"json\"\n")
}

///|
fn generate_global_config_template() -> String {
  let buf = StringBuilder::new()
  buf.write_string("# indexion global configuration\n")
  buf.write_string("# See: https://github.com/trkbt10/indexion\n")
  buf.write_string("\n")
  buf.write_string("[global]\n")
  buf.write_string("# kgfs_dir = \"~/kgfs\"  # Override KGF specs location\n")
  buf.write_string("\n")
  buf.write_string("[reconcile]\n")
  buf.write_string("# threshold_seconds = 60\n")
  buf.write_string("# max_candidates = 200\n")
  buf.write_string("\n")
  write_reconcile_sections(buf)
  buf.write_string("\n")
  write_digest_section(buf)
  buf.to_string()
}

///|
fn generate_project_config_template() -> String {
  let buf = StringBuilder::new()
  buf.write_string("# indexion project configuration\n")
  buf.write_string("# See: https://github.com/trkbt10/indexion\n")
  buf.write_string("\n")
  buf.write_string("[indexion]\n")
  buf.write_string("# inherit = true  # Set to false to ignore global config\n")
  buf.write_string("\n")
  buf.write_string("[reconcile]\n")
  buf.write_string(
    "# doc_scope = \"package-docs\"  # package-docs | tree-docs | custom\n",
  )
  buf.write_string("# doc_paths = [\"README.md\", \"docs/**/*.md\"]\n")
  buf.write_string("# threshold_seconds = 60\n")
  buf.write_string("# max_candidates = 200\n")
  buf.write_string("\n")
  write_reconcile_sections(buf)
  buf.write_string("\n")
  write_digest_section(buf)
  buf.to_string()
}

///|
fn generate_gitignore() -> String {
  let buf = StringBuilder::new()
  buf.write_string("# indexion local files (not committed)\n")
  buf.write_string("cache/\n")
  buf.write_string("local/\n")
  buf.to_string()
}
