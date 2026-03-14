///|
/// Structured refactoring plan renderer.
/// Generates comprehensive, actionable refactoring documents with:
/// - Architecture overview
/// - Problem identification
/// - Phased implementation plan
/// - Checklists

///|
/// Render as structured refactoring document (Markdown).
pub fn render_structured(
  plan : RefactorPlanJSON,
  project_name : String,
) -> String {
  let buf = StringBuilder::new()
  let date = get_current_date()

  // Header
  buf.write_string("# ")
  buf.write_string(project_name)
  buf.write_string(" Refactoring Plan\n\n")
  buf.write_string("**Date**: ")
  buf.write_string(date)
  buf.write_string("\n")
  buf.write_string("**Target Directory**: `")
  buf.write_string(plan.config.target_dir)
  buf.write_string("`\n")
  buf.write_string("**Files Analyzed**: ")
  buf.write_string(plan.summary.total_files_analyzed.to_string())
  buf.write_string("\n\n")
  buf.write_string("---\n\n")

  // 1. Current Analysis
  buf.write_string("## 1. Current Analysis\n\n")
  render_architecture_section(buf, plan)
  render_dependency_section(buf, plan)
  render_problems_section(buf, plan)

  // 2. Refactoring Plan
  buf.write_string("## 2. Refactoring Plan\n\n")
  render_phases(buf, plan)

  // 3. Priority and Estimates
  buf.write_string("## 3. Priority & Estimates\n\n")
  render_priority_table(buf, plan)

  // 4. Execution Checklist
  buf.write_string("## 4. Execution Checklist\n\n")
  render_checklists(buf, plan)

  // Appendix
  buf.write_string("---\n\n")
  buf.write_string("## Appendix: Similarity Analysis\n\n")
  render_similarity_summary(buf, plan)

  buf.to_string()
}

///|
fn get_current_date() -> String {
  "2026-03-05"
}

///|
fn render_architecture_section(
  buf : StringBuilder,
  plan : RefactorPlanJSON,
) -> Unit {
  buf.write_string("### 1.1 Architecture Overview\n\n")
  buf.write_string("```\n")

  let dir_files : Map[String, Array[String]] = Map::new()
  for cluster in plan.clusters {
    for file in cluster.files {
      let dir = extract_directory(file)
      match dir_files.get(dir) {
        Some(arr) => {
          let mut exists = false
          for existing in arr {
            if existing == file {
              exists = true
              break
            }
          }
          if not(exists) {
            arr.push(file)
          }
        }
        None => dir_files.set(dir, [file])
      }
    }
  }

  let dirs : Array[String] = []
  for dir, _ in dir_files {
    dirs.push(dir)
  }
  sort_strings(dirs)

  for dir in dirs {
    buf.write_string(dir)
    buf.write_string("/\n")
    match dir_files.get(dir) {
      Some(files) => {
        sort_strings(files)
        for file in files {
          buf.write_string("├── ")
          buf.write_string(extract_filename(file))
          buf.write_string("\n")
        }
      }
      None => ()
    }
  }
  buf.write_string("```\n\n")
}

///|
fn render_dependency_section(
  buf : StringBuilder,
  plan : RefactorPlanJSON,
) -> Unit {
  buf.write_string("### 1.2 Dependencies\n\n")
  buf.write_string("```\n")

  let dirs : Array[String] = []
  for cluster in plan.clusters {
    for file in cluster.files {
      let dir = extract_directory(file)
      let mut exists = false
      for d in dirs {
        if d == dir {
          exists = true
          break
        }
      }
      if not(exists) {
        dirs.push(dir)
      }
    }
  }
  sort_strings(dirs)

  if dirs.length() > 0 {
    for i, dir in dirs {
      buf.write_string(dir)
      if i < dirs.length() - 1 {
        buf.write_string(" ← ")
      }
    }
    buf.write_string("\n")
  }
  buf.write_string("```\n\n")
}

///|
fn render_problems_section(
  buf : StringBuilder,
  plan : RefactorPlanJSON,
) -> Unit {
  buf.write_string("### 1.3 Identified Issues\n\n")
  buf.write_string("| Category | Issue | Severity |\n")
  buf.write_string("|---------|------|--------|\n")

  let mut dup_count = 0
  let dup_funcs : Array[String] = []

  for cluster in plan.clusters {
    for dup in cluster.duplicates {
      dup_count = dup_count + 1
      match dup.func_name {
        Some(name) => {
          let mut exists = false
          for f in dup_funcs {
            if f == name {
              exists = true
              break
            }
          }
          if not(exists) {
            dup_funcs.push(name)
          }
        }
        None => ()
      }
    }
  }

  if dup_count > 0 {
    buf.write_string("| **Code Duplication** | ")
    if dup_funcs.length() > 0 {
      buf.write_string("`")
      buf.write_string(dup_funcs[0])
      buf.write_string("` duplicated")
    } else {
      buf.write_string(dup_count.to_string())
      buf.write_string(" duplicated")
    }
    buf.write_string(" | High |\n")
  }

  for cluster in plan.clusters {
    if cluster.pairs.length() > 0 {
      let max_sim = cluster.pairs[0].similarity
      if max_sim > 0.9 {
        buf.write_string("| **High Similarity** | `")
        buf.write_string(extract_filename(cluster.pairs[0].file1))
        buf.write_string("` ↔ `")
        buf.write_string(extract_filename(cluster.pairs[0].file2))
        buf.write_string("` ")
        buf.write_string(@common.format_percent(max_sim))
        buf.write_string(" similar | High |\n")
      }
    }
  }

  let large_clusters = plan.clusters.filter(fn(c) { c.files.length() > 3 })
  if large_clusters.length() > 0 {
    buf.write_string(
      "| **Responsibility** | Multiple related files may indicate unclear responsibilities | Medium |\n",
    )
  }

  buf.write_string("\n")
}

///|
fn render_phases(buf : StringBuilder, plan : RefactorPlanJSON) -> Unit {
  let mut phase_num = 1

  let has_duplicates = plan.clusters
    .iter()
    .any(fn(c) { c.duplicates.length() > 0 })
  if has_duplicates {
    buf.write_string("### Phase ")
    buf.write_string(phase_num.to_string())
    buf.write_string(": Utility Extraction\n\n")
    buf.write_string("**Purpose**: Eliminate duplicate code\n\n")

    let all_funcs : Array[String] = []
    let shared_modules : Array[String] = []
    for cluster in plan.clusters {
      if cluster.suggestions.shared_module.length() > 0 {
        let mut exists = false
        for m in shared_modules {
          if m == cluster.suggestions.shared_module {
            exists = true
            break
          }
        }
        if not(exists) {
          shared_modules.push(cluster.suggestions.shared_module)
        }
      }
      for name in cluster.suggestions.functions_to_extract {
        let mut exists = false
        for f in all_funcs {
          if f == name {
            exists = true
            break
          }
        }
        if not(exists) {
          all_funcs.push(name)
        }
      }
    }

    buf.write_string("**Actions**:\n")
    for i, mod_path in shared_modules {
      buf.write_string((i + 1).to_string())
      buf.write_string(". `")
      buf.write_string(mod_path)
      buf.write_string("` (create)\n")
    }

    if all_funcs.length() > 0 {
      buf.write_string("\n**Functions to Extract**:\n")
      for func in all_funcs {
        buf.write_string("- `")
        buf.write_string(func)
        buf.write_string("`\n")
      }
    }
    buf.write_string("\n---\n\n")
    phase_num = phase_num + 1
  }

  let high_sim_clusters = plan.clusters.filter(fn(c) {
    c.pairs.length() > 0 && c.pairs[0].similarity > 0.8
  })
  if high_sim_clusters.length() > 0 {
    buf.write_string("### Phase ")
    buf.write_string(phase_num.to_string())
    buf.write_string(": File Consolidation\n\n")
    buf.write_string("**Purpose**: Consolidate highly similar files\n\n")

    for cluster in high_sim_clusters {
      buf.write_string("#### Group ")
      buf.write_string(cluster.group_id.to_string())
      buf.write_string("\n\n")
      buf.write_string("**Target Files**:\n")
      for file in cluster.files {
        buf.write_string("- `")
        buf.write_string(file)
        buf.write_string("`\n")
      }
      buf.write_string("\n**Actions**:\n")
      buf.write_string("1. Extract common patterns\n")
      buf.write_string("2. Keep only differences in each file\n")
      buf.write_string("3. Run tests\n\n")
    }
    buf.write_string("---\n\n")
    phase_num = phase_num + 1
  }

  if plan.clusters.length() > 2 {
    buf.write_string("### Phase ")
    buf.write_string(phase_num.to_string())
    buf.write_string(": Architecture Improvement\n\n")
    buf.write_string("**Purpose**: Improve package structure\n\n")
    buf.write_string("**Considerations**:\n")
    buf.write_string("- Introduce common interfaces\n")
    buf.write_string("- Trait-based design\n")
    buf.write_string("- Dependency cleanup\n\n")
  }
}

///|
fn render_priority_table(buf : StringBuilder, plan : RefactorPlanJSON) -> Unit {
  buf.write_string("| Phase | Description | Effort | Priority | Depends |\n")
  buf.write_string("|-------|------|------|--------|------|\n")

  let mut phase_num = 1
  let has_duplicates = plan.clusters
    .iter()
    .any(fn(c) { c.duplicates.length() > 0 })

  if has_duplicates {
    buf.write_string("| ")
    buf.write_string(phase_num.to_string())
    buf.write_string(" | Utility Extraction | 1d | High | None |\n")
    phase_num = phase_num + 1
  }

  let high_sim_clusters = plan.clusters.filter(fn(c) {
    c.pairs.length() > 0 && c.pairs[0].similarity > 0.8
  })
  if high_sim_clusters.length() > 0 {
    buf.write_string("| ")
    buf.write_string(phase_num.to_string())
    buf.write_string(" | File Consolidation | 2d | High | Phase 1 |\n")
    phase_num = phase_num + 1
  }

  if plan.clusters.length() > 2 {
    buf.write_string("| ")
    buf.write_string(phase_num.to_string())
    buf.write_string(" | Architecture Improvement | 3d | Low | Phase 1-")
    buf.write_string((phase_num - 1).to_string())
    buf.write_string(" |\n")
  }

  buf.write_string("\n")
}

///|
fn render_checklists(buf : StringBuilder, plan : RefactorPlanJSON) -> Unit {
  let mut phase_num = 1
  let has_duplicates = plan.clusters
    .iter()
    .any(fn(c) { c.duplicates.length() > 0 })

  if has_duplicates {
    buf.write_string("### Phase ")
    buf.write_string(phase_num.to_string())
    buf.write_string(" Completion Criteria\n\n")

    let shared_modules : Array[String] = []
    for cluster in plan.clusters {
      if cluster.suggestions.shared_module.length() > 0 {
        let mut exists = false
        for m in shared_modules {
          if m == cluster.suggestions.shared_module {
            exists = true
            break
          }
        }
        if not(exists) {
          shared_modules.push(cluster.suggestions.shared_module)
        }
      }
    }

    for mod_path in shared_modules {
      buf.write_string("- [ ] `")
      buf.write_string(mod_path)
      buf.write_string("` created\n")
    }
    buf.write_string("- [ ] Duplicate code removed\n")
    buf.write_string("- [ ] All tests pass\n\n")
    phase_num = phase_num + 1
  }

  let high_sim_clusters = plan.clusters.filter(fn(c) {
    c.pairs.length() > 0 && c.pairs[0].similarity > 0.8
  })
  if high_sim_clusters.length() > 0 {
    buf.write_string("### Phase ")
    buf.write_string(phase_num.to_string())
    buf.write_string(" Completion Criteria\n\n")
    buf.write_string("- [ ] Common patterns extracted\n")
    buf.write_string("- [ ] Similarity reduced below 80%\n")
    buf.write_string("- [ ] All tests pass\n\n")
  }
}

///|
fn render_similarity_summary(
  buf : StringBuilder,
  plan : RefactorPlanJSON,
) -> Unit {
  buf.write_string("### Analysis Settings\n\n")
  buf.write_string("- **Threshold**: ")
  buf.write_string(@common.format_percent(plan.config.threshold))
  buf.write_string("\n")
  buf.write_string("- **Strategy**: ")
  buf.write_string(plan.config.strategy)
  buf.write_string("\n\n")

  for cluster in plan.clusters {
    buf.write_string("### Group ")
    buf.write_string(cluster.group_id.to_string())
    buf.write_string(" (")
    buf.write_string(cluster.files.length().to_string())
    buf.write_string(" files")
    if cluster.pairs.length() > 0 {
      buf.write_string(", max: ")
      buf.write_string(@common.format_percent(cluster.pairs[0].similarity))
    }
    buf.write_string(")\n\n")

    buf.write_string("**Files**:\n")
    for file in cluster.files {
      buf.write_string("- `")
      buf.write_string(file)
      buf.write_string("`\n")
    }
    buf.write_string("\n")

    if cluster.pairs.length() > 0 {
      buf.write_string("**Similarity Pairs**:\n\n")
      buf.write_string("| File 1 | File 2 | % |\n")
      buf.write_string("|--------|--------|---|\n")
      for pair in cluster.pairs {
        buf.write_string("| `")
        buf.write_string(extract_filename(pair.file1))
        buf.write_string("` | `")
        buf.write_string(extract_filename(pair.file2))
        buf.write_string("` | ")
        buf.write_string(@common.format_percent(pair.similarity))
        buf.write_string(" |\n")
      }
      buf.write_string("\n")
    }

    if cluster.duplicates.length() > 0 {
      buf.write_string("**Duplicate Code Blocks** (")
      buf.write_string(cluster.duplicates.length().to_string())
      buf.write_string(" blocks):\n\n")

      let mut current_pair = ""
      let mut shown_count = 0
      for dup in cluster.duplicates {
        let pair_key = dup.file1 + ":" + dup.file2
        if pair_key != current_pair {
          current_pair = pair_key
          shown_count = 0
          buf.write_string("**`")
          buf.write_string(extract_filename(dup.file1))
          buf.write_string("` ↔ `")
          buf.write_string(extract_filename(dup.file2))
          buf.write_string("`**:\n")
        }
        if shown_count < 3 {
          buf.write_string("- ")
          buf.write_string(dup.line_count.to_string())
          buf.write_string(" lines @ L")
          buf.write_string(dup.start_line1.to_string())
          buf.write_string("/L")
          buf.write_string(dup.start_line2.to_string())
          match dup.func_name {
            Some(name) => {
              buf.write_string(" (`")
              buf.write_string(name)
              buf.write_string("`)")
            }
            None => ()
          }
          buf.write_string("\n")
          shown_count = shown_count + 1
        }
      }
      buf.write_string("\n")
    }

    buf.write_string("---\n\n")
  }
}

// Helper functions

///|
fn extract_directory(path : String) -> String {
  let chars = path.to_array()
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' || chars[i] == '\\' {
      last_slash = i
    }
  }
  if last_slash < 0 {
    return "."
  }
  let result : Array[Char] = []
  for i = 0; i < last_slash; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
fn extract_filename(path : String) -> String {
  let chars = path.to_array()
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' || chars[i] == '\\' {
      last_slash = i
    }
  }
  if last_slash < 0 {
    return path
  }
  let result : Array[Char] = []
  for i = last_slash + 1; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
fn sort_strings(arr : Array[String]) -> Unit {
  for i = 0; i < arr.length(); i = i + 1 {
    for j = i + 1; j < arr.length(); j = j + 1 {
      if arr[j] < arr[i] {
        let tmp = arr[i]
        arr[i] = arr[j]
        arr[j] = tmp
      }
    }
  }
}
