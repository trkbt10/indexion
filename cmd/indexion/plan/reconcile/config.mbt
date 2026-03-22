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
/// Define the reconcile command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "reconcile",
    about="Detect implementation/documentation drift",
    options=[
      @argparse.OptionArg("output", short='o', about=@help.output),
      @argparse.OptionArg(
        "format",
        about="Output format: json, md, github-issue",
        default_values=["json"],
      ),
      @argparse.OptionArg(
        "scope",
        about="Doc scope preset: custom, package-docs, tree-docs",
      ),
      @argparse.OptionArg(
        "specs-dir",
        about="KGF specs directory (default: auto-detect)",
      ),
      @argparse.OptionArg(
        "index-dir",
        about="Cache directory (default: .indexion/cache/reconcile)",
      ),
      @argparse.OptionArg(
        "config",
        about="Explicit config file (.indexion.toml or .json)",
      ),
      @argparse.OptionArg(
        "review-results",
        about="Apply logical review decisions from JSON",
      ),
      @argparse.OptionArg(
        "threshold-seconds",
        about="Drift threshold in seconds",
        default_values=["60"],
      ),
      @argparse.OptionArg(
        "max-candidates",
        about="Maximum candidates in output",
        default_values=["200"],
      ),
      @argparse.OptionArg(
        "doc",
        action=Append,
        about="Restrict document paths (repeatable)",
      ),
      @argparse.OptionArg(
        "doc-spec",
        action=Append,
        about="Restrict document KGF specs (repeatable)",
      ),
      @argparse.OptionArg("logical-review", about="queue or off", default_values=[
        "queue",
      ]),
    ],
    flags=[
      @argparse.FlagArg::new(
        "no-file-fallback",
        about="Disable basename/file-path fallback matching",
      ),
      @argparse.FlagArg::new(
        "git",
        about="Prefer git timestamps over file mtimes",
      ),
      @argparse.FlagArg::new(
        "mtime-only",
        about="Skip git timestamps and rely on file mtimes",
      ),
      @argparse.FlagArg::new("no-parallel", about="Disable parallel processing"),
    ],
    positionals=[
      @argparse.PositionArg(
        "directory",
        num_args=@argparse.ValueRange(lower=0),
        about="Target directory to analyze",
      ),
    ],
  )
}

///|
fn is_from_argv(matches : @argparse.Matches, key : String) -> Bool {
  match matches.sources.get(key) {
    Some(@argparse.Argv) => true
    _ => false
  }
}

///|
fn parse_args_state_from_matches(
  matches : @argparse.Matches,
) -> ParsedArgsState {
  let mut config = ReconcileConfig::default()
  // output
  match matches.values.get("output") {
    Some(arr) => if arr.length() > 0 { config = { ..config, output: arr[0] } }
    _ => ()
  }
  // format
  match matches.values.get("format") {
    Some(arr) => if arr.length() > 0 { config = { ..config, format: arr[0] } }
    _ => ()
  }
  // scope
  match matches.values.get("scope") {
    Some(arr) =>
      if arr.length() > 0 {
        config = update_documents_scope_name(config, arr[0])
      }
    _ => ()
  }
  // specs-dir
  match matches.values.get("specs-dir") {
    Some(arr) =>
      if arr.length() > 0 {
        config = { ..config, specs_dir: arr[0] }
      }
    _ => ()
  }
  // index-dir
  match matches.values.get("index-dir") {
    Some(arr) =>
      if arr.length() > 0 {
        config = { ..config, index_dir: arr[0] }
      }
    _ => ()
  }
  // config
  match matches.values.get("config") {
    Some(arr) =>
      if arr.length() > 0 {
        config = { ..config, config_path: arr[0] }
      }
    _ => ()
  }
  // review-results
  match matches.values.get("review-results") {
    Some(arr) =>
      if arr.length() > 0 {
        config = { ..config, review_results_path: arr[0] }
      }
    _ => ()
  }
  // threshold-seconds
  match matches.values.get("threshold-seconds") {
    Some(arr) =>
      if arr.length() > 0 {
        config = { ..config, threshold_seconds: @common.parse_int(arr[0]) }
      }
    _ => ()
  }
  // max-candidates
  match matches.values.get("max-candidates") {
    Some(arr) =>
      if arr.length() > 0 {
        config = { ..config, max_candidates: @common.parse_int(arr[0]) }
      }
    _ => ()
  }
  // doc (repeatable)
  let explicit_doc_paths = is_from_argv(matches, "doc")
  match matches.values.get("doc") {
    Some(arr) if explicit_doc_paths =>
      config = replace_document_paths(config, arr.copy())
    _ => ()
  }
  // doc-spec (repeatable)
  let explicit_doc_specs = is_from_argv(matches, "doc-spec")
  match matches.values.get("doc-spec") {
    Some(arr) if explicit_doc_specs =>
      config = replace_document_specs(config, arr.copy())
    _ => ()
  }
  // logical-review
  match matches.values.get("logical-review") {
    Some(arr) =>
      if arr.length() > 0 {
        config = { ..config, logical_review_mode: arr[0] }
      }
    _ => ()
  }
  // no-file-fallback (flag)
  match matches.flags.get("no-file-fallback") {
    Some(true) => config = { ..config, allow_file_fallback: false }
    _ => ()
  }
  // git (flag)
  match matches.flags.get("git") {
    Some(true) => config = { ..config, git_preferred: true }
    _ => ()
  }
  // mtime-only (flag)
  match matches.flags.get("mtime-only") {
    Some(true) =>
      config = { ..config, git_preferred: false, mtime_fallback: true }
    _ => ()
  }
  // no-parallel (flag)
  match matches.flags.get("no-parallel") {
    Some(true) => config = { ..config, parallel: false }
    _ => ()
  }
  // directory (positional)
  match matches.values.get("directory") {
    Some(arr) =>
      if arr.length() > 0 {
        config = { ..config, target_dir: arr[0] }
      }
    _ => ()
  }
  {
    config,
    explicit_format: is_from_argv(matches, "format"),
    explicit_doc_scope: is_from_argv(matches, "scope"),
    explicit_specs_dir: is_from_argv(matches, "specs-dir"),
    explicit_index_dir: is_from_argv(matches, "index-dir"),
    explicit_review_results_path: is_from_argv(matches, "review-results"),
    explicit_threshold_seconds: is_from_argv(matches, "threshold-seconds"),
    explicit_max_candidates: is_from_argv(matches, "max-candidates"),
    explicit_doc_paths,
    explicit_doc_specs,
    explicit_allow_file_fallback: is_from_argv(matches, "no-file-fallback"),
    explicit_git_preferred: is_from_argv(matches, "git") ||
    is_from_argv(matches, "mtime-only"),
    explicit_mtime_fallback: is_from_argv(matches, "mtime-only"),
    explicit_logical_review_mode: is_from_argv(matches, "logical-review"),
  }
}

///|
/// Parse argparse matches and merge with file-based configuration.
pub fn resolve_config_from_matches(
  matches : @argparse.Matches,
) -> ReconcileConfig {
  let parsed = parse_args_state_from_matches(matches)
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
