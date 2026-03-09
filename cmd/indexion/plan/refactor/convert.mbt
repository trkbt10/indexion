///|
/// Convert RefactorPlanJSON to PlanDocument IR.

///|
/// Convert refactoring plan to PlanDocument.
pub fn refactor_to_plan_document(
  plan : RefactorPlanJSON,
  project_name : String
) -> @plan_types.PlanDocument {
  let doc = @plan_types.PlanDocument::new(project_name + " Refactoring Plan")
  doc.set_description("Code similarity analysis and refactoring recommendations.")
  // Metadata
  doc.set_meta("project_name", project_name)
  doc.set_meta("threshold", plan.config.threshold.to_string())
  doc.set_meta("strategy", plan.config.strategy)
  doc.set_meta("total_clusters", plan.summary.total_clusters.to_string())
  doc.set_meta("max_similarity", format_similarity(plan.summary.max_similarity))
  doc.set_meta("labels", "refactoring,code-quality")
  // Summary section
  doc.add_section(build_summary_section(plan))
  // Clusters section
  if plan.clusters.length() > 0 {
    doc.add_section(build_clusters_section(plan))
  }
  // Action Items section
  doc.add_section(build_refactor_actions(plan))
  doc
}

///|
fn build_summary_section(plan : RefactorPlanJSON) -> @plan_types.PlanSection {
  let pairs : Array[(String, String)] = []
  pairs.push(("Target Directory", plan.config.target_dir))
  pairs.push(("Threshold", format_similarity(plan.config.threshold)))
  pairs.push(("Strategy", plan.config.strategy))
  pairs.push(("Files Analyzed", plan.summary.total_files_analyzed.to_string()))
  pairs.push(("Similar Clusters", plan.summary.total_clusters.to_string()))
  pairs.push(("Max Similarity", format_similarity(plan.summary.max_similarity)))
  @plan_types.PlanSection::new(
    "summary",
    "Analysis Summary",
    @plan_types.SectionContent::keyvalue(pairs),
  )
}

///|
fn build_clusters_section(plan : RefactorPlanJSON) -> @plan_types.PlanSection {
  let nested : Array[@plan_types.PlanSection] = []
  for cluster in plan.clusters {
    nested.push(build_cluster_subsection(cluster))
  }
  @plan_types.PlanSection::new(
    "clusters",
    "Similar Code Clusters",
    @plan_types.SectionContent::nested(nested),
  )
}

///|
fn build_cluster_subsection(cluster : ClusterJSON) -> @plan_types.PlanSection {
  let items : Array[@plan_types.ListItem] = []
  // Files in cluster
  for file in cluster.files {
    items.push(@plan_types.ListItem::simple("`" + file + "`"))
  }
  // Add similarity info
  for pair in cluster.pairs {
    let desc = format_similarity(pair.similarity) + " similar"
    items.push(@plan_types.ListItem::with_desc("`" + pair.file1 + "` ↔ `" + pair.file2 + "`", desc))
  }
  @plan_types.PlanSection::new(
    "group" + cluster.group_id.to_string(),
    "Group " + cluster.group_id.to_string() + " (" + cluster.files.length().to_string() + " files)",
    @plan_types.SectionContent::list(items),
  )
}

///|
fn build_refactor_actions(plan : RefactorPlanJSON) -> @plan_types.PlanSection {
  let nested : Array[@plan_types.PlanSection] = []
  // High priority: > 90% similarity
  let high_sim : Array[@plan_types.ChecklistItem] = []
  for cluster in plan.clusters {
    for pair in cluster.pairs {
      if pair.similarity >= 0.9 {
        high_sim.push(@plan_types.ChecklistItem::with_priority(
          "Merge or extract common code: `" + short_name(pair.file1) + "` ↔ `" + short_name(pair.file2) + "` (" + format_similarity(pair.similarity) + ")",
          1,
        ))
      }
    }
  }
  if high_sim.length() > 0 {
    nested.push(@plan_types.PlanSection::new(
      "priority1",
      "Priority 1: Near Duplicates (>90%)",
      @plan_types.SectionContent::checklist(high_sim),
    ))
  }
  // Medium priority: 80-90% similarity
  let med_sim : Array[@plan_types.ChecklistItem] = []
  for cluster in plan.clusters {
    for pair in cluster.pairs {
      if pair.similarity >= 0.8 && pair.similarity < 0.9 {
        med_sim.push(@plan_types.ChecklistItem::with_priority(
          "Consider extracting shared logic: `" + short_name(pair.file1) + "` ↔ `" + short_name(pair.file2) + "` (" + format_similarity(pair.similarity) + ")",
          2,
        ))
      }
    }
  }
  if med_sim.length() > 0 {
    nested.push(@plan_types.PlanSection::new(
      "priority2",
      "Priority 2: High Similarity (80-90%)",
      @plan_types.SectionContent::checklist(med_sim),
    ))
  }
  // Suggested modules
  let suggested : Array[@plan_types.ChecklistItem] = []
  for cluster in plan.clusters {
    if cluster.suggestions.shared_module.length() > 0 {
      let mut funcs = ""
      if cluster.suggestions.functions_to_extract.length() > 0 {
        funcs = " (extract: "
        for i, f in cluster.suggestions.functions_to_extract {
          if i > 0 {
            funcs = funcs + ", "
          }
          funcs = funcs + "`" + f + "`"
          if i >= 2 {
            funcs = funcs + "..."
            break
          }
        }
        funcs = funcs + ")"
      }
      suggested.push(@plan_types.ChecklistItem::with_priority(
        "Create shared module `" + cluster.suggestions.shared_module + "`" + funcs,
        3,
      ))
    }
  }
  if suggested.length() > 0 {
    nested.push(@plan_types.PlanSection::new(
      "suggestions",
      "Suggested Shared Modules",
      @plan_types.SectionContent::checklist(suggested),
    ))
  }
  @plan_types.PlanSection::new(
    "actions",
    "Action Items",
    @plan_types.SectionContent::nested(nested),
  )
}

///|
fn format_similarity(sim : Double) -> String {
  let percent = (sim * 100.0).to_int()
  percent.to_string() + "%"
}

///|
fn short_name(path : String) -> String {
  let chars = path.to_array()
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last_slash = i
    }
  }
  if last_slash >= 0 && last_slash + 1 < chars.length() {
    let result : Array[Char] = []
    for i = last_slash + 1; i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    path
  }
}
