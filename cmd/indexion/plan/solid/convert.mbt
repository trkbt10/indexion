///|
/// Convert solid analysis results to PlanDocument IR.

///|
/// Intermediate JSON representation for solid plan.
pub struct SolidPlanJSON {
  config : SolidConfigJSON
  summary : SolidSummaryJSON
  extractions : Array[ExtractionGroup]
  unmatched : Array[UnmatchedFile]
  function_matches : Array[CrossFunctionMatch]
  extraction_tasks : Array[ExtractionTask]
}

///|
/// Configuration section of the solid plan output.
pub struct SolidConfigJSON {
  sources : Array[String]
  target : String
  threshold : Double
  rules_count : Int
  from_dirs : Array[String] // original --from directories for path reconstruction
}

///|
/// Summary statistics for the solid plan.
pub struct SolidSummaryJSON {
  total_matches : Int
  matched_by_rules : Int
  unmatched_count : Int
  path_match_count : Int
  content_match_count : Int
  function_match_count : Int
  extraction_task_count : Int
}

///|
/// Group of files to extract to a common target path.
pub struct ExtractionGroup {
  target_path : String
  files : Array[ExtractionFile]
}

///|
/// A file candidate for extraction with similarity score.
pub struct ExtractionFile {
  relative_path : String
  similarity : Double
  action : String // "Extract" or "Extract (review diff)"
  source1 : String // first source file (dirname:path)
  source2 : String // second source file (dirname:path)
}

///|
/// A file that matched similarity threshold but no extraction rule.
pub struct UnmatchedFile {
  relative_path : String
  similarity : Double
  source1 : String
  source2 : String
}

///|
/// Convert solid plan to PlanDocument.
pub fn solid_to_plan_document(plan : SolidPlanJSON) -> @plan_types.PlanDocument {
  let title = "Solidification Plan"
  let doc = @plan_types.PlanDocument::new(title)
  doc.set_description(
    "Extract common code from multiple packages into a shared location.",
  )
  // Metadata
  doc.set_meta("threshold", @common.format_percent(plan.config.threshold))
  doc.set_meta("rules_count", plan.config.rules_count.to_string())
  doc.set_meta("labels", "refactoring,code-sharing,consolidation")
  // Summary section
  doc.add_section(build_summary_section(plan))
  // Extraction sections (file-level)
  if plan.extractions.length() > 0 {
    for group in plan.extractions {
      doc.add_section(build_extraction_section(group))
    }
  }
  // Function-level matches section
  if plan.function_matches.length() > 0 {
    doc.add_section(build_function_matches_section(plan.function_matches))
  }
  // Agent extraction tasks section
  if plan.extraction_tasks.length() > 0 {
    for task in plan.extraction_tasks {
      doc.add_section(
        build_extraction_task_section(task, plan.config.from_dirs),
      )
    }
  }
  // Unmatched section
  if plan.unmatched.length() > 0 {
    doc.add_section(build_unmatched_section(plan.unmatched, plan.config.from_dirs))
  }
  doc
}

///|
fn build_summary_section(plan : SolidPlanJSON) -> @plan_types.PlanSection {
  let pairs : Array[(String, String)] = []
  // Sources
  let sources_str = plan.config.sources
    .iter()
    .fold(init="", fn(acc, s) {
      if acc.length() == 0 {
        s
      } else {
        acc + ", " + s
      }
    })
  pairs.push(("Sources", sources_str))
  pairs.push(("Target", plan.config.target))
  pairs.push(("Threshold", @common.format_percent(plan.config.threshold)))
  pairs.push(("Rules Defined", plan.config.rules_count.to_string()))
  pairs.push(("Path Matches", plan.summary.path_match_count.to_string()))
  pairs.push(("Content Matches", plan.summary.content_match_count.to_string()))
  pairs.push(
    ("Function Matches", plan.summary.function_match_count.to_string()),
  )
  pairs.push(
    ("Extraction Tasks", plan.summary.extraction_task_count.to_string()),
  )
  pairs.push(("Files Matched (by rules)", plan.summary.matched_by_rules.to_string()))
  pairs.push(("Files Unmatched", plan.summary.unmatched_count.to_string()))
  @plan_types.PlanSection::new(
    "summary",
    "Summary",
    @plan_types.SectionContent::keyvalue(pairs),
  )
}

///|
fn build_extraction_section(group : ExtractionGroup) -> @plan_types.PlanSection {
  let table = @plan_types.TableData::new([
    "Similarity", "File", "Sources", "Action",
  ])
  for file in group.files {
    let sources = @common.get_dirname_prefix(file.source1) +
      " / " +
      @common.get_dirname_prefix(file.source2)
    table.add_row([
      @common.format_percent(file.similarity),
      "`" + file.relative_path + "`",
      sources,
      file.action,
    ])
  }
  @plan_types.PlanSection::new(
    "extract-" + sanitize_id(group.target_path),
    "Extract to `" + group.target_path + "`",
    @plan_types.SectionContent::table(table),
  )
}

///|
fn build_function_matches_section(
  matches : Array[CrossFunctionMatch],
) -> @plan_types.PlanSection {
  let table = @plan_types.TableData::new([
    "Similarity", "Function", "Source 1", "Source 2",
  ])
  for m in matches {
    let func_display = if m.func_name1 == m.func_name2 {
      "`" + m.func_name1 + "`"
    } else {
      "`" + m.func_name1 + "` / `" + m.func_name2 + "`"
    }
    table.add_row([
      @common.format_percent(m.similarity),
      func_display,
      m.dir1 + ": " + @common.get_relative_part(m.file1),
      m.dir2 + ": " + @common.get_relative_part(m.file2),
    ])
  }
  @plan_types.PlanSection::new(
    "function-matches",
    "Cross-Directory Function Duplicates",
    @plan_types.SectionContent::table(table),
  )
}

///|
/// Resolve a display_name (dirname:relative_path) back to a filesystem path
/// using the original from_dirs.
fn resolve_display_name(
  display_name : String,
  from_dirs : Array[String],
) -> String {
  let dirname = @common.get_dirname_prefix(display_name)
  let rel = @common.get_relative_part(display_name)
  // Find the from_dir whose last path component matches dirname
  for dir in from_dirs {
    let dir_trimmed = @pipeline.trim_trailing_slash(dir)
    let parts = @common.split_by_slash(dir_trimmed)
    if parts.length() > 0 && parts[parts.length() - 1] == dirname {
      return dir_trimmed + "/" + rel
    }
  }
  // Fallback: return as-is
  display_name
}

///|
fn build_extraction_task_section(
  task : ExtractionTask,
  from_dirs : Array[String],
) -> @plan_types.PlanSection {
  let items : Array[@plan_types.ListItem] = []
  items.push(
    @plan_types.ListItem::with_desc(
      "Target",
      "`" + task.target_path + "`",
    ),
  )
  items.push(
    @plan_types.ListItem::with_desc(
      "Strategy",
      task.merge_strategy,
    ),
  )
  items.push(
    @plan_types.ListItem::with_desc(
      "Confidence",
      @common.format_percent(task.confidence),
    ),
  )
  // List functions to extract with full paths and code preview
  for func in task.functions {
    let locations_str = func.source_locations
      .iter()
      .fold(init="", fn(acc, loc) {
        let full_path = resolve_display_name(loc.file, from_dirs)
        let entry = "`" + full_path + "`"
        if acc.length() == 0 {
          entry
        } else {
          acc + ", " + entry
        }
      })
    items.push(
      @plan_types.ListItem::with_desc(
        "`" + func.name + "` (" +
        @common.format_percent(func.similarity) +
        ", " +
        func.line_count.to_string() +
        " lines)",
        "from: " + locations_str,
      ),
    )
    // Include code preview for agent consumption
    if func.preview.length() > 0 {
      items.push(
        @plan_types.ListItem::with_desc(
          "preview",
          "\n```\n" + func.preview + "\n```",
        ),
      )
    }
  }
  // List affected source files with full paths
  let affected = task.source_files
    .iter()
    .fold(init="", fn(acc, f) {
      let full = resolve_display_name(f, from_dirs)
      if acc.length() == 0 {
        "`" + full + "`"
      } else {
        acc + ", `" + full + "`"
      }
    })
  items.push(
    @plan_types.ListItem::with_desc("Affected files", affected),
  )
  @plan_types.PlanSection::new(
    "task-" + task.task_id.to_string(),
    "Extraction Task #" + task.task_id.to_string(),
    @plan_types.SectionContent::list(items),
  )
}

///|
fn build_unmatched_section(
  unmatched : Array[UnmatchedFile],
  from_dirs : Array[String],
) -> @plan_types.PlanSection {
  let items : Array[@plan_types.ListItem] = []
  for file in unmatched {
    let full1 = resolve_display_name(file.source1, from_dirs)
    let full2 = resolve_display_name(file.source2, from_dirs)
    items.push(
      @plan_types.ListItem::with_desc(
        "`" + file.relative_path + "`",
        @common.format_percent(file.similarity) +
        " similar (`" +
        full1 +
        "` / `" +
        full2 +
        "`)",
      ),
    )
  }
  @plan_types.PlanSection::new(
    "unmatched",
    "Not Matched (no rule)",
    @plan_types.SectionContent::list(items),
  )
}

// format_percent: use @common (SoT)

///|
fn sanitize_id(s : String) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  for c in chars {
    if c == '/' || c == ' ' || c == '.' {
      result.push('-')
    } else {
      result.push(c)
    }
  }
  String::from_array(result)
}
