///|
priv struct ParsedArgsState {
  config : ReconcileConfig
  explicit_format : Bool
  explicit_doc_scope : Bool
  explicit_specs_dir : Bool
  explicit_index_dir : Bool
  explicit_review_results_path : Bool
  explicit_threshold_seconds : Bool
  explicit_max_candidates : Bool
  explicit_doc_paths : Bool
  explicit_doc_specs : Bool
  explicit_allow_file_fallback : Bool
  explicit_git_preferred : Bool
  explicit_mtime_fallback : Bool
  explicit_logical_review_mode : Bool
}

///|
fn update_documents_scope_name(
  config : ReconcileConfig,
  scope_name : String,
) -> ReconcileConfig {
  let documents = @config_paths.resolve_reconcile_document_scope(
    scope_name,
    doc_paths=config.documents.doc_paths,
    doc_specs=config.documents.doc_specs,
  )
  { ..config, documents, }
}

///|
fn append_document_path(
  config : ReconcileConfig,
  path : String,
) -> ReconcileConfig {
  let doc_paths = config.documents.doc_paths.copy()
  doc_paths.push(path)
  let documents = @config_paths.resolve_reconcile_document_scope(
    config.documents.scope_name,
    doc_paths~,
    doc_specs=config.documents.doc_specs,
  )
  { ..config, documents, }
}

///|
fn replace_document_paths(
  config : ReconcileConfig,
  doc_paths : Array[String],
) -> ReconcileConfig {
  let documents = @config_paths.resolve_reconcile_document_scope(
    config.documents.scope_name,
    doc_paths~,
    doc_specs=config.documents.doc_specs,
  )
  { ..config, documents, }
}

///|
fn append_document_spec(
  config : ReconcileConfig,
  spec : String,
) -> ReconcileConfig {
  let doc_specs = config.documents.doc_specs.copy()
  doc_specs.push(spec)
  let documents = @config_paths.resolve_reconcile_document_scope(
    config.documents.scope_name,
    doc_paths=config.documents.doc_paths,
    doc_specs~,
  )
  { ..config, documents, }
}

///|
fn replace_document_specs(
  config : ReconcileConfig,
  doc_specs : Array[String],
) -> ReconcileConfig {
  let documents = @config_paths.resolve_reconcile_document_scope(
    config.documents.scope_name,
    doc_paths=config.documents.doc_paths,
    doc_specs~,
  )
  { ..config, documents, }
}

///|
fn parsed_args_state() -> ParsedArgsState {
  {
    config: ReconcileConfig::default(),
    explicit_format: false,
    explicit_doc_scope: false,
    explicit_specs_dir: false,
    explicit_index_dir: false,
    explicit_review_results_path: false,
    explicit_threshold_seconds: false,
    explicit_max_candidates: false,
    explicit_doc_paths: false,
    explicit_doc_specs: false,
    explicit_allow_file_fallback: false,
    explicit_git_preferred: false,
    explicit_mtime_fallback: false,
    explicit_logical_review_mode: false,
  }
}

///|
fn parse_args_state(args : Array[String], start_idx : Int) -> ParsedArgsState {
  let mut state = parsed_args_state()
  let mut config = state.config
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg.has_prefix("--output=") || arg.has_prefix("-o=") {
      let prefix_len = if arg.has_prefix("--output=") { 9 } else { 3 }
      config = { ..config, output: @common.get_arg_value(arg, prefix_len) }
    } else if arg.has_prefix("--format=") {
      config = { ..config, format: @common.get_arg_value(arg, 9) }
      state = { ..state, explicit_format: true }
    } else if arg.has_prefix("--scope=") {
      config = update_documents_scope_name(config, @common.get_arg_value(arg, 8))
      state = { ..state, explicit_doc_scope: true }
    } else if arg.has_prefix("--specs=") || arg.has_prefix("--specs-dir=") {
      let prefix_len = if arg.has_prefix("--specs-dir=") { 12 } else { 8 }
      config = { ..config, specs_dir: @common.get_arg_value(arg, prefix_len) }
      state = { ..state, explicit_specs_dir: true }
    } else if arg.has_prefix("--index-dir=") {
      config = { ..config, index_dir: @common.get_arg_value(arg, 12) }
      state = { ..state, explicit_index_dir: true }
    } else if arg.has_prefix("--config=") {
      config = { ..config, config_path: @common.get_arg_value(arg, 9) }
    } else if arg.has_prefix("--review-results=") {
      config = { ..config, review_results_path: @common.get_arg_value(arg, 17) }
      state = { ..state, explicit_review_results_path: true }
    } else if arg.has_prefix("--threshold-seconds=") {
      config = {
        ..config,
        threshold_seconds: @common.parse_int(@common.get_arg_value(arg, 20)),
      }
      state = { ..state, explicit_threshold_seconds: true }
    } else if arg.has_prefix("--max-candidates=") {
      config = { ..config, max_candidates: @common.parse_int(@common.get_arg_value(arg, 17)) }
      state = { ..state, explicit_max_candidates: true }
    } else if arg.has_prefix("--doc=") {
      let path = @common.get_arg_value(arg, 6)
      config = if state.explicit_doc_paths {
        append_document_path(config, path)
      } else {
        replace_document_paths(config, [path])
      }
      state = { ..state, explicit_doc_paths: true }
    } else if arg.has_prefix("--doc-spec=") {
      let spec = @common.get_arg_value(arg, 11)
      config = if state.explicit_doc_specs {
        append_document_spec(config, spec)
      } else {
        replace_document_specs(config, [spec])
      }
      state = { ..state, explicit_doc_specs: true }
    } else if arg == "--no-file-fallback" {
      config = { ..config, allow_file_fallback: false }
      state = { ..state, explicit_allow_file_fallback: true }
    } else if arg == "--mtime-only" {
      config = { ..config, git_preferred: false, mtime_fallback: true }
      state = {
        ..state,
        explicit_git_preferred: true,
        explicit_mtime_fallback: true,
      }
    } else if arg == "--logical-review=off" {
      config = { ..config, logical_review_mode: "off" }
      state = { ..state, explicit_logical_review_mode: true }
    } else if arg == "--logical-review=queue" {
      config = { ..config, logical_review_mode: "queue" }
      state = { ..state, explicit_logical_review_mode: true }
    } else if not(arg.has_prefix("-")) && config.target_dir.length() == 0 {
      config = { ..config, target_dir: arg }
    }
  }
  { ..state, config, }
}

///|
pub fn parse_args(args : Array[String], start_idx : Int) -> ReconcileConfig {
  parse_args_state(args, start_idx).config
}

///|
fn resolve_specs_dir(target_dir : String, specs_dir? : String = "") -> String {
  @config_paths.resolve_reconcile_specs_dir(
    target_dir,
    explicit_specs_dir=specs_dir,
  )
}

///|
fn merge_file_config(
  parsed : ParsedArgsState,
  file_config : @config_paths.ReconcileFileConfig,
) -> ReconcileConfig {
  let config = parsed.config
  {
    ..config,
    format: if parsed.explicit_format {
      config.format
    } else {
      match file_config.format {
        Some(value) => value
        None => config.format
      }
    },
    index_dir: if parsed.explicit_index_dir {
      config.index_dir
    } else {
      match file_config.index_dir {
        Some(value) => value
        None => config.index_dir
      }
    },
    review_results_path: if parsed.explicit_review_results_path {
      config.review_results_path
    } else {
      match file_config.review_results_path {
        Some(value) => value
        None => config.review_results_path
      }
    },
    documents: @config_paths.resolve_reconcile_document_scope(
      if parsed.explicit_doc_scope {
        config.documents.scope_name
      } else {
        match file_config.doc_scope {
          Some(value) => value
          None => config.documents.scope_name
        }
      },
      doc_paths=if parsed.explicit_doc_paths {
        config.documents.doc_paths
      } else {
        match file_config.doc_paths {
          Some(values) => values
          None => config.documents.doc_paths
        }
      },
      doc_specs=if parsed.explicit_doc_specs {
        config.documents.doc_specs
      } else {
        match file_config.doc_specs {
          Some(values) => values
          None => config.documents.doc_specs
        }
      },
    ),
    threshold_seconds: if parsed.explicit_threshold_seconds {
      config.threshold_seconds
    } else {
      match file_config.threshold_seconds {
        Some(value) => value
        None => config.threshold_seconds
      }
    },
    max_candidates: if parsed.explicit_max_candidates {
      config.max_candidates
    } else {
      match file_config.max_candidates {
        Some(value) => value
        None => config.max_candidates
      }
    },
    allow_file_fallback: if parsed.explicit_allow_file_fallback {
      config.allow_file_fallback
    } else {
      match file_config.allow_file_fallback {
        Some(value) => value
        None => config.allow_file_fallback
      }
    },
    git_preferred: if parsed.explicit_git_preferred {
      config.git_preferred
    } else {
      match file_config.git_preferred {
        Some(value) => value
        None => config.git_preferred
      }
    },
    mtime_fallback: if parsed.explicit_mtime_fallback {
      config.mtime_fallback
    } else {
      match file_config.mtime_fallback {
        Some(value) => value
        None => config.mtime_fallback
      }
    },
    logical_review_mode: if parsed.explicit_logical_review_mode {
      config.logical_review_mode
    } else {
      match file_config.logical_review_mode {
        Some(value) => value
        None => config.logical_review_mode
      }
    },
  }
}

///|
fn apply_doc_scope(config : ReconcileConfig) -> ReconcileConfig {
  let resolved = @config_paths.resolve_reconcile_document_scope(
    config.documents.scope_name,
    doc_paths=config.documents.doc_paths,
    doc_specs=config.documents.doc_specs,
  )
  { ..config, documents: resolved }
}

///|
fn resolve_inherited_config_path(
  target_dir : String,
  resolved_value : String,
  project_value : String?,
  project_config_path : String,
  global_value : String?,
  global_config_path : String?,
  fallback : String,
) -> String {
  match project_value {
    Some(_) =>
      @config_paths.resolve_config_path_value(
        target_dir, project_config_path, resolved_value,
      )
    None =>
      match global_value {
        Some(_) =>
          match global_config_path {
            Some(path) =>
              @config_paths.resolve_config_path_value(
                target_dir, path, resolved_value,
              )
            None => @config_paths.resolve_path(target_dir, resolved_value)
          }
        None => fallback
      }
  }
}

///|
pub fn resolve_config(args : Array[String], start_idx : Int) -> ReconcileConfig {
  let parsed = parse_args_state(args, start_idx)
  let cli = parsed.config
  let target_dir = @config_paths.normalize_path(
    if cli.target_dir.length() > 0 {
      cli.target_dir
    } else {
      "."
    },
  )
  let config_path = @config_paths.find_indexion_config_path(
    target_dir,
    explicit_path=cli.config_path,
  )
  let effective = @config_paths.resolve_effective_reconcile_config(config_path)
  let file_config = effective.merged
  let base = {
    ..cli,
    target_dir,
    config_path,
    specs_dir: resolve_specs_dir(target_dir, specs_dir=cli.specs_dir),
  }
  let merged0 = merge_file_config({ ..parsed, config: base }, file_config)
  let merged = if (parsed.explicit_doc_paths || parsed.explicit_doc_specs) &&
    not(parsed.explicit_doc_scope) {
    update_documents_scope_name(merged0, "custom")
  } else {
    merged0
  }
  apply_doc_scope({
    ..merged,
    index_dir: if parsed.explicit_index_dir {
      @config_paths.resolve_path(target_dir, merged.index_dir)
    } else {
      resolve_inherited_config_path(
        target_dir,
        merged.index_dir,
        effective.project.reconcile.index_dir,
        config_path,
        effective.global.reconcile.index_dir,
        effective.global_config_path,
        @config_paths.default_reconcile_index_dir(target_dir),
      )
    },
    review_results_path: if parsed.explicit_review_results_path {
      @config_paths.resolve_path(target_dir, merged.review_results_path)
    } else {
      resolve_inherited_config_path(
        target_dir,
        merged.review_results_path,
        effective.project.reconcile.review_results_path,
        config_path,
        effective.global.reconcile.review_results_path,
        effective.global_config_path,
        "",
      )
    },
    specs_dir: if parsed.explicit_specs_dir {
      @config_paths.resolve_path(target_dir, merged.specs_dir)
    } else {
      resolve_specs_dir(target_dir)
    },
  })
}

///|
pub fn show_help() -> Unit {
  println("indexion plan reconcile - Detect implementation/documentation drift")
  println("")
  println("Usage:")
  println("  indexion plan reconcile [options] <directory>")
  println("")
  println("Options:")
  println("  --output=FILE, -o=     Output file path (default: stdout)")
  println(
    "  --format=FORMAT        Output format: json, md, github-issue (default: json)",
  )
  println(
    "  --scope=MODE           Doc scope preset: custom, package-docs, tree-docs",
  )
  println("  --specs=DIR            KGF specs directory (default: auto-detect)")
  println(
    "  --index-dir=DIR        Cache directory (default: .indexion/cache/reconcile)",
  )
  println(
    "  --config=FILE          Explicit config file (.indexion.toml or .json)",
  )
  println("  --review-results=FILE  Apply logical review decisions from JSON")
  println("  --threshold-seconds=N  Drift threshold in seconds (default: 60)")
  println(
    "  --max-candidates=N     Maximum candidates in output (default: 200)",
  )
  println("  --doc=GLOB             Restrict document paths (repeatable)")
  println("  --doc-spec=NAME        Restrict document KGF specs (repeatable)")
  println(
    "  --no-file-fallback     Disable basename/file-path fallback matching",
  )
  println(
    "  --mtime-only           Skip git timestamps and rely on file mtimes",
  )
  println("  --logical-review=MODE  queue or off (default: queue)")
  println("  --help                 Show this help message")
  println("")
  println("Config files:")
  println("  .indexion.toml is preferred over .indexion.json")
  println("")
  println("Examples:")
  println("  indexion plan reconcile .")
  println("  indexion plan reconcile --format=md src/")
  println(
    "  indexion plan reconcile --scope=package-docs cmd/indexion/plan/reconcile",
  )
  println("  indexion plan reconcile --scope=tree-docs cmd/indexion/plan")
  println(
    "  indexion plan reconcile --doc='docs/**/*.md' --doc='spec/**/*.toml' .",
  )
}
