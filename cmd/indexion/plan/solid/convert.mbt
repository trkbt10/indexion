///|
/// Convert solid analysis results to PlanDocument IR.

///|
/// Intermediate JSON representation for solid plan.
pub struct SolidPlanJSON {
  config : SolidConfigJSON
  summary : SolidSummaryJSON
  extractions : Array[ExtractionGroup]
  unmatched : Array[UnmatchedFile]
}

///|
pub struct SolidConfigJSON {
  sources : Array[String]
  target : String
  threshold : Double
  rules_count : Int
}

///|
pub struct SolidSummaryJSON {
  total_matches : Int
  matched_by_rules : Int
  unmatched_count : Int
}

///|
pub struct ExtractionGroup {
  target_path : String
  files : Array[ExtractionFile]
}

///|
pub struct ExtractionFile {
  relative_path : String
  similarity : Double
  action : String // "Extract" or "Extract (review diff)"
}

///|
pub struct UnmatchedFile {
  relative_path : String
  similarity : Double
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
  doc.set_meta("threshold", format_percent(plan.config.threshold))
  doc.set_meta("rules_count", plan.config.rules_count.to_string())
  doc.set_meta("labels", "refactoring,code-sharing,consolidation")
  // Summary section
  doc.add_section(build_summary_section(plan))
  // Extraction sections
  for group in plan.extractions {
    doc.add_section(build_extraction_section(group))
  }
  // Unmatched section
  if plan.unmatched.length() > 0 {
    doc.add_section(build_unmatched_section(plan.unmatched))
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
  pairs.push(("Threshold", format_percent(plan.config.threshold)))
  pairs.push(("Rules Defined", plan.config.rules_count.to_string()))
  pairs.push(("Files Matched", plan.summary.matched_by_rules.to_string()))
  pairs.push(("Files Unmatched", plan.summary.unmatched_count.to_string()))
  @plan_types.PlanSection::new(
    "summary",
    "Summary",
    @plan_types.SectionContent::keyvalue(pairs),
  )
}

///|
fn build_extraction_section(group : ExtractionGroup) -> @plan_types.PlanSection {
  let table = @plan_types.TableData::new(["Similarity", "File", "Action"])
  for file in group.files {
    table.add_row([
      format_percent(file.similarity),
      "`" + file.relative_path + "`",
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
fn build_unmatched_section(
  unmatched : Array[UnmatchedFile],
) -> @plan_types.PlanSection {
  let items : Array[@plan_types.ListItem] = []
  for file in unmatched {
    items.push(
      @plan_types.ListItem::with_desc(
        "`" + file.relative_path + "`",
        format_percent(file.similarity) + " similar",
      ),
    )
  }
  @plan_types.PlanSection::new(
    "unmatched",
    "Not Matched (no rule)",
    @plan_types.SectionContent::list(items),
  )
}

///|
fn format_percent(d : Double) -> String {
  let percent = (d * 100.0).to_int()
  percent.to_string() + "%"
}

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
