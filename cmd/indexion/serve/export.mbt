///|
/// # indexion serve export
///
/// Export a self-contained static site (wiki + explorer) for GitHub Pages.
/// The output directory can be deployed directly — it contains the SPA
/// assets (HTML/JS/CSS), wiki data, and explorer data (graph + digest index).

///|
/// Wrap data in ApiResponse envelope: {"ok":true,"data":...}
fn wrap_ok(data_json : String) -> String {
  "{\"ok\":true,\"data\":" + data_json + "}"
}

///|
/// Write a string to a file, creating parent directories as needed.
fn write_file(path : String, content : String) -> Bool {
  let parent = @common.parent_dir(path)
  @config.ensure_dir_recursive(parent)
  @fs.write_string_to_file(path, content) catch {
    @fs.IOError(msg) => {
      @digest_cli.log_error("Failed to write " + path + ": " + msg)
      return false
    }
  }
  true
}

///|
/// Copy a single file (binary-safe).
fn copy_file(src : String, dst : String) -> Bool {
  let parent = @common.parent_dir(dst)
  @config.ensure_dir_recursive(parent)
  let content = @fs.read_file_to_bytes(src) catch {
    @fs.IOError(msg) => {
      @digest_cli.log_error("Failed to read " + src + ": " + msg)
      return false
    }
  }
  @fs.write_bytes_to_file(dst, content) catch {
    @fs.IOError(msg) => {
      @digest_cli.log_error("Failed to write " + dst + ": " + msg)
      return false
    }
  }
  true
}

///|
/// Recursively copy a directory tree.
fn copy_dir_recursive(src_dir : String, dst_dir : String) -> Int {
  let mut count = 0
  @config.ensure_dir_recursive(dst_dir)
  let entries = @fs.read_dir(src_dir) catch { _ => return 0 }
  for entry in entries {
    let src_path = src_dir + "/" + entry
    let dst_path = dst_dir + "/" + entry
    let is_dir = @fs.is_dir(src_path) catch { _ => false }
    if is_dir {
      count = count + copy_dir_recursive(src_path, dst_path)
    } else if copy_file(src_path, dst_path) {
      count = count + 1
    }
  }
  count
}

///|
/// Resolve the SPA assets directory.
/// Priority: --static-dir flag > installed wiki dir > error.
fn resolve_static_dir(matches : @argparse.Matches) -> String? {
  // Explicit --static-dir
  match matches.values.get("static-dir") {
    Some(vals) =>
      if vals.length() > 0 && vals[0].length() > 0 {
        if @fs.path_exists(vals[0] + "/index.html") {
          return Some(vals[0])
        }
      }
    None => ()
  }
  // Installed wiki directory (same as serve uses)
  match @config.get_wiki_install_dir() {
    Some(dir) => if @fs.path_exists(dir + "/index.html") { return Some(dir) }
    None => ()
  }
  None
}

///|
pub async fn run_export(matches : @argparse.Matches) -> Unit {
  // Parse serve config for digest build
  let wiki_file_config = @config.load_effective_wiki_config(".indexion.toml")
  let serve_config = {
    ..ServeConfig::from_matches(matches).apply_embedding_file_config(
      @digest_cli.load_embedding_file_config(),
    ),
    wiki_config: wiki_file_config,
  }
  let output_dir = match matches.values.get("output") {
    Some(vals) => if vals.length() > 0 { vals[0] } else { "dist/pages" }
    None => "dist/pages"
  }
  @digest_cli.log_progress("Exporting static site to " + output_dir + "...")
  // 1. Resolve and copy SPA assets
  let static_dir = match resolve_static_dir(matches) {
    Some(dir) => dir
    None => {
      @digest_cli.log_error(
        "No SPA assets found. Specify --static-dir or install the wiki frontend.",
      )
      return
    }
  }
  @digest_cli.log_progress("Copying SPA assets from " + static_dir + "...")
  let asset_count = copy_dir_recursive(static_dir, output_dir)
  @digest_cli.log_progress("Copied " + asset_count.to_string() + " SPA files.")
  // Static Pages cannot hit the live /api/wiki/assets handler, so publish
  // project wiki assets at the same API-shaped path used in config JSON.
  let wiki_asset_count = match
    @wiki_workspace.resolve_project_wiki_dir(serve_config.workspace_dir) {
    Some(dir) =>
      copy_dir_recursive(
        @wiki_workspace.assets_dir(dir),
        output_dir + "/api/wiki/assets",
      )
    None => 0
  }
  if wiki_asset_count > 0 {
    @digest_cli.log_progress(
      "Copied " + wiki_asset_count.to_string() + " wiki asset files.",
    )
  }
  // 2. Build or load digest data (graph + index) — reuses serve logic
  let digest_cli_config = make_digest_cli_config(serve_config)
  let digest_config = @digest_cli.build_digest_config(digest_cli_config)
  let state = match do_load(serve_config, digest_cli_config, digest_config) {
    Some(s) => s
    None =>
      match do_build(serve_config, digest_cli_config, digest_config) {
        Some(s) => s
        None => {
          @digest_cli.log_error("Failed to build digest data for export.")
          return
        }
      }
  }
  // 3. Write JSON data as extensionless files.
  //    Paths come from build_get_routes() — the SoT shared with
  //    the HTTP server routing. The SPA uses the same paths via HttpClient.
  let routes = build_get_routes(state, serve_config)
  let mut json_count = 0
  routes.each(fn(path, data) {
    // path includes /api prefix (e.g. "/api/health")
    if write_file(output_dir + path, wrap_ok(data)) {
      json_count = json_count + 1
    }
  })
  // 4. SPA routing fallback + GitHub Pages markers
  if @fs.path_exists(output_dir + "/index.html") {
    let _ = copy_file(output_dir + "/index.html", output_dir + "/404.html")
  }
  let _ = write_file(output_dir + "/.nojekyll", "")

  @digest_cli.log_progress(
    "Done: " +
    asset_count.to_string() +
    " SPA files + " +
    json_count.to_string() +
    " API routes -> " +
    output_dir,
  )
}
