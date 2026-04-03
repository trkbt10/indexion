///|
/// Convert DocAnalysis to PlanDocument IR.

///|
/// Convert documentation analysis to PlanDocument.
pub fn to_plan_document(
  analysis : DocAnalysis,
  info : ProjectInfo,
  name : String,
) -> @plan_types.PlanDocument {
  let project_name = if name.length() > 0 { name } else { info.name }
  let doc = @plan_types.PlanDocument::new(project_name + " Documentation Plan")
  doc.set_description("Documentation coverage analysis and improvement plan.")
  // Metadata
  doc.set_meta("project_name", project_name)
  doc.set_meta("version", info.version)
  doc.set_meta(
    "coverage",
    @common.format_percent(analysis.coverage_percent / 100.0),
  )
  doc.set_meta("documented", analysis.total_documented.to_string())
  doc.set_meta("total", analysis.total_pub_items.to_string())
  doc.set_meta("labels", "documentation,plan")
  // Coverage Summary section
  doc.add_section(build_coverage_section(analysis))
  // Critical Missing section
  if analysis.critical_missing.length() > 0 {
    doc.add_section(build_missing_section(analysis))
  }
  // Package Inventory section
  doc.add_section(build_inventory_section(analysis))
  // Action Items section
  doc.add_section(build_action_section(analysis))
  doc
}

///|
fn build_coverage_section(analysis : DocAnalysis) -> @plan_types.PlanSection {
  // Calculate stats
  let mut fn_total = 0
  let mut fn_doc = 0
  let mut type_total = 0
  let mut type_doc = 0
  for pkg in analysis.packages {
    for item in pkg.pub_items {
      if item.kind_category == "function" {
        fn_total = fn_total + 1
        if item.has_doc {
          fn_doc = fn_doc + 1
        }
      } else {
        type_total = type_total + 1
        if item.has_doc {
          type_doc = type_doc + 1
        }
      }
    }
  }
  // Build table
  let table = @plan_types.TableData::new([
    "Category", "Documented", "Total", "Coverage",
  ])
  table.add_row([
    "Functions",
    fn_doc.to_string(),
    fn_total.to_string(),
    @common.format_percent(
      if fn_total > 0 {
        fn_doc.to_double() / fn_total.to_double()
      } else {
        1.0
      },
    ),
  ])
  table.add_row([
    "Types",
    type_doc.to_string(),
    type_total.to_string(),
    @common.format_percent(
      if type_total > 0 {
        type_doc.to_double() / type_total.to_double()
      } else {
        1.0
      },
    ),
  ])
  @plan_types.PlanSection::new(
    "coverage",
    "Coverage Summary",
    @plan_types.SectionContent::table(table),
  )
}

///|
fn build_missing_section(analysis : DocAnalysis) -> @plan_types.PlanSection {
  let items : Array[@plan_types.ChecklistItem] = []
  let max_items = 30
  let mut count = 0
  for item in analysis.critical_missing {
    if count >= max_items {
      break
    }
    items.push(
      @plan_types.ChecklistItem::with_desc(
        item.kind + " " + item.name,
        item.file + ":" + item.line.to_string(),
      ),
    )
    count = count + 1
  }
  @plan_types.PlanSection::new(
    "missing",
    "Critical Missing Documentation",
    @plan_types.SectionContent::checklist(items),
  )
}

///|
fn build_inventory_section(analysis : DocAnalysis) -> @plan_types.PlanSection {
  let table = @plan_types.TableData::new([
    "Package", "Pub Items", "Documented", "Coverage", "README",
  ])
  for pkg in analysis.packages {
    let cov = if pkg.total_pub > 0 {
      pkg.documented.to_double() / pkg.total_pub.to_double()
    } else {
      1.0
    }
    table.add_row([
      "`" + pkg.path + "`",
      pkg.total_pub.to_string(),
      pkg.documented.to_string(),
      @common.format_percent(cov),
      if pkg.has_readme {
        "Yes"
      } else {
        "No"
      },
    ])
  }
  @plan_types.PlanSection::new(
    "inventory",
    "Package Inventory",
    @plan_types.SectionContent::table(table),
  )
}

///|
fn build_action_section(analysis : DocAnalysis) -> @plan_types.PlanSection {
  let nested_sections : Array[@plan_types.PlanSection] = []
  // Priority 1: Zero coverage
  let zero_cov = analysis.packages.filter(fn(p) {
    p.total_pub > 0 && p.documented == 0
  })
  if zero_cov.length() > 0 {
    let items : Array[@plan_types.ChecklistItem] = []
    for pkg in zero_cov {
      items.push(
        @plan_types.ChecklistItem::with_priority(
          "Document `" +
          pkg.path +
          "` (" +
          pkg.total_pub.to_string() +
          " pub items)",
          1,
        ),
      )
    }
    nested_sections.push(
      @plan_types.PlanSection::new(
        "priority1",
        "Priority 1: Zero Coverage Packages",
        @plan_types.SectionContent::checklist(items),
      ),
    )
  }
  // Priority 2: Missing README
  let no_readme = analysis.packages.filter(fn(p) { !p.has_readme })
  if no_readme.length() > 0 {
    let items : Array[@plan_types.ChecklistItem] = []
    for pkg in no_readme {
      items.push(
        @plan_types.ChecklistItem::with_priority(
          "Add README.md to `" + pkg.path + "`",
          2,
        ),
      )
    }
    nested_sections.push(
      @plan_types.PlanSection::new(
        "priority2",
        "Priority 2: Missing README",
        @plan_types.SectionContent::checklist(items),
      ),
    )
  }
  // Priority 3: Low coverage
  let low_cov = analysis.packages.filter(fn(p) {
    p.total_pub > 0 &&
    p.documented > 0 &&
    p.documented.to_double() / p.total_pub.to_double() < 0.5
  })
  if low_cov.length() > 0 {
    let items : Array[@plan_types.ChecklistItem] = []
    for pkg in low_cov {
      let cov = pkg.documented.to_double() / pkg.total_pub.to_double()
      items.push(
        @plan_types.ChecklistItem::with_priority(
          "Improve `" +
          pkg.path +
          "` coverage (currently " +
          @common.format_percent(cov) +
          ")",
          3,
        ),
      )
    }
    nested_sections.push(
      @plan_types.PlanSection::new(
        "priority3",
        "Priority 3: Low Coverage (<50%)",
        @plan_types.SectionContent::checklist(items),
      ),
    )
  }
  @plan_types.PlanSection::new(
    "actions",
    "Action Items",
    @plan_types.SectionContent::nested(nested_sections),
  )
}
