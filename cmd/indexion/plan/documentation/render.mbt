///|
/// Render documentation analysis output.

///|
fn get_current_date() -> String {
  "2026-03-05"
}

///|
/// Render full documentation plan.
pub fn render_full(
  analysis : DocAnalysis,
  info : ProjectInfo,
  name : String,
) -> String {
  let buf = StringBuilder::new()
  let date = get_current_date()
  let project_name = if name.length() > 0 { name } else { info.name }

  // Header
  buf.write_string("# ")
  buf.write_string(project_name)
  buf.write_string(" Documentation Plan\n\n")
  buf.write_string("**Date**: ")
  buf.write_string(date)
  buf.write_string("\n")
  buf.write_string("**Coverage**: ")
  buf.write_string(@common.format_percent(analysis.coverage_percent / 100.0))
  buf.write_string(" (")
  buf.write_string(analysis.total_documented.to_string())
  buf.write_string("/")
  buf.write_string(analysis.total_pub_items.to_string())
  buf.write_string(" pub items documented)\n\n")
  buf.write_string("---\n\n")

  // Coverage summary
  render_coverage_section(buf, analysis)

  // Critical missing
  if analysis.critical_missing.length() > 0 {
    render_missing_section(buf, analysis)
  }

  // Package inventory
  render_package_inventory(buf, analysis)

  // Action items
  render_action_items(buf, analysis)

  buf.to_string()
}

///|
/// Render coverage analysis only.
pub fn render_coverage(analysis : DocAnalysis, name : String) -> String {
  let buf = StringBuilder::new()

  buf.write_string("# ")
  buf.write_string(name)
  buf.write_string(" Documentation Coverage\n\n")
  buf.write_string("**Overall Coverage**: ")
  buf.write_string(@common.format_percent(analysis.coverage_percent / 100.0))
  buf.write_string(" (")
  buf.write_string(analysis.total_documented.to_string())
  buf.write_string("/")
  buf.write_string(analysis.total_pub_items.to_string())
  buf.write_string(")\n\n")

  render_coverage_section(buf, analysis)
  render_package_inventory(buf, analysis)

  buf.to_string()
}

///|
/// Render README template only.
pub fn render_readme_template(
  analysis : DocAnalysis,
  info : ProjectInfo,
) -> String {
  generate_readme_content(analysis, info)
}

///|
fn render_coverage_section(buf : StringBuilder, analysis : DocAnalysis) -> Unit {
  buf.write_string("## Coverage Summary\n\n")

  // Coverage bar visualization
  let filled = (analysis.coverage_percent / 10.0).to_int()
  buf.write_string("```\n")
  buf.write_string("[")
  for i = 0; i < 10; i = i + 1 {
    if i < filled {
      buf.write_string("█")
    } else {
      buf.write_string("░")
    }
  }
  buf.write_string("] ")
  buf.write_string(@common.format_percent(analysis.coverage_percent / 100.0))
  buf.write_string("\n```\n\n")

  // Stats breakdown
  let mut fn_total = 0
  let mut fn_doc = 0
  let mut type_total = 0
  let mut type_doc = 0
  for pkg in analysis.packages {
    for item in pkg.pub_items {
      if item.kind == "fn" {
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

  buf.write_string("| Category | Documented | Total | Coverage |\n")
  buf.write_string("|----------|------------|-------|----------|\n")
  buf.write_string("| Functions | ")
  buf.write_string(fn_doc.to_string())
  buf.write_string(" | ")
  buf.write_string(fn_total.to_string())
  buf.write_string(" | ")
  buf.write_string(
    @common.format_percent(
      if fn_total > 0 {
        fn_doc.to_double() / fn_total.to_double()
      } else {
        1.0
      },
    ),
  )
  buf.write_string(" |\n")
  buf.write_string("| Types | ")
  buf.write_string(type_doc.to_string())
  buf.write_string(" | ")
  buf.write_string(type_total.to_string())
  buf.write_string(" | ")
  buf.write_string(
    @common.format_percent(
      if type_total > 0 {
        type_doc.to_double() / type_total.to_double()
      } else {
        1.0
      },
    ),
  )
  buf.write_string(" |\n\n")
}

///|
fn render_missing_section(buf : StringBuilder, analysis : DocAnalysis) -> Unit {
  buf.write_string("## Critical Missing Documentation\n\n")
  buf.write_string(
    "The following public APIs lack documentation (high priority):\n\n",
  )

  let mut current_file = ""
  let mut count = 0
  let max_items = 30 // Limit output
  for item in analysis.critical_missing {
    if count >= max_items {
      buf.write_string("\n... and ")
      buf.write_string(
        (analysis.critical_missing.length() - max_items).to_string(),
      )
      buf.write_string(" more items\n")
      break
    }
    if item.file != current_file {
      current_file = item.file
      buf.write_string("\n**`")
      buf.write_string(item.file)
      buf.write_string("`**:\n")
    }
    buf.write_string("- [ ] `")
    buf.write_string(item.kind)
    buf.write_string(" ")
    buf.write_string(item.name)
    buf.write_string("` (L")
    buf.write_string(item.line.to_string())
    buf.write_string(")\n")
    count = count + 1
  }
  buf.write_string("\n")
}

///|
fn render_package_inventory(
  buf : StringBuilder,
  analysis : DocAnalysis,
) -> Unit {
  buf.write_string("## Package Inventory\n\n")
  buf.write_string("| Package | Pub Items | Documented | Coverage | README |\n")
  buf.write_string("|---------|-----------|------------|----------|--------|\n")

  for pkg in analysis.packages {
    let cov = if pkg.total_pub > 0 {
      pkg.documented.to_double() / pkg.total_pub.to_double()
    } else {
      1.0
    }
    buf.write_string("| `")
    buf.write_string(pkg.path)
    buf.write_string("` | ")
    buf.write_string(pkg.total_pub.to_string())
    buf.write_string(" | ")
    buf.write_string(pkg.documented.to_string())
    buf.write_string(" | ")
    buf.write_string(@common.format_percent(cov))
    buf.write_string(" | ")
    if pkg.has_readme {
      buf.write_string("✓")
    } else {
      buf.write_string("✗")
    }
    buf.write_string(" |\n")
  }
  buf.write_string("\n")
}

///|
fn render_action_items(buf : StringBuilder, analysis : DocAnalysis) -> Unit {
  buf.write_string("## Action Items\n\n")

  // Priority 1: Packages with 0% coverage
  let zero_cov = analysis.packages.filter(fn(p) {
    p.total_pub > 0 && p.documented == 0
  })
  if zero_cov.length() > 0 {
    buf.write_string("### Priority 1: Zero Coverage Packages\n\n")
    for pkg in zero_cov {
      buf.write_string("- [ ] Document `")
      buf.write_string(pkg.path)
      buf.write_string("` (")
      buf.write_string(pkg.total_pub.to_string())
      buf.write_string(" pub items)\n")
    }
    buf.write_string("\n")
  }

  // Priority 2: Missing README
  let no_readme = analysis.packages.filter(fn(p) { not(p.has_readme) })
  if no_readme.length() > 0 {
    buf.write_string("### Priority 2: Missing README\n\n")
    for pkg in no_readme {
      buf.write_string("- [ ] Add README.md to `")
      buf.write_string(pkg.path)
      buf.write_string("`\n")
    }
    buf.write_string("\n")
  }

  // Priority 3: Low coverage (< 50%)
  let low_cov = analysis.packages.filter(fn(p) {
    p.total_pub > 0 &&
    p.documented > 0 &&
    p.documented.to_double() / p.total_pub.to_double() < 0.5
  })
  if low_cov.length() > 0 {
    buf.write_string("### Priority 3: Low Coverage (<50%)\n\n")
    for pkg in low_cov {
      let cov = pkg.documented.to_double() / pkg.total_pub.to_double()
      buf.write_string("- [ ] Improve `")
      buf.write_string(pkg.path)
      buf.write_string("` coverage (currently ")
      buf.write_string(@common.format_percent(cov))
      buf.write_string(")\n")
    }
    buf.write_string("\n")
  }

  // Summary
  buf.write_string("### Summary\n\n")
  buf.write_string("- Total packages: ")
  buf.write_string(analysis.packages.length().to_string())
  buf.write_string("\n")
  buf.write_string("- Packages needing work: ")
  buf.write_string((zero_cov.length() + low_cov.length()).to_string())
  buf.write_string("\n")
  buf.write_string("- Missing READMEs: ")
  buf.write_string(no_readme.length().to_string())
  buf.write_string("\n")
}

///|
fn generate_readme_content(
  analysis : DocAnalysis,
  info : ProjectInfo,
) -> String {
  let buf = StringBuilder::new()

  // Title
  buf.write_string("# ")
  buf.write_string(info.name)
  buf.write_string("\n\n")

  // Badges placeholder
  buf.write_string("[![License](https://img.shields.io/badge/license-")
  buf.write_string(if info.license.length() > 0 { info.license } else { "MIT" })
  buf.write_string("-blue.svg)](LICENSE)\n\n")

  // Description
  if info.description.length() > 0 {
    buf.write_string(info.description)
    buf.write_string("\n\n")
  } else {
    buf.write_string("<!-- Add project description here -->\n\n")
  }

  // Features/Keywords
  if info.keywords.length() > 0 {
    buf.write_string("## Features\n\n")
    for kw in info.keywords {
      buf.write_string("- ")
      buf.write_string(kw)
      buf.write_string("\n")
    }
    buf.write_string("\n")
  }

  // Installation
  buf.write_string("## Installation\n\n")
  buf.write_string("```bash\n")
  buf.write_string("moon add ")
  buf.write_string(info.name)
  buf.write_string("\n")
  buf.write_string("```\n\n")

  // Quick Start
  buf.write_string("## Quick Start\n\n")
  buf.write_string("```moonbit\n")
  // Find main types to show usage
  let main_types : Array[PubItem] = []
  for pkg in analysis.packages {
    for item in pkg.pub_items {
      if item.kind == "struct" || item.kind == "type" {
        main_types.push(item)
        if main_types.length() >= 3 {
          break
        }
      }
    }
    if main_types.length() >= 3 {
      break
    }
  }
  if main_types.length() > 0 {
    buf.write_string("// Example usage\n")
    buf.write_string("let instance = @")
    // Extract package name from file path
    let pkg_name = extract_package_from_path(main_types[0].file)
    buf.write_string(pkg_name)
    buf.write_string(".")
    buf.write_string(main_types[0].name)
    buf.write_string("::new()\n")
  } else {
    buf.write_string("// Add usage example here\n")
  }
  buf.write_string("```\n\n")

  // API Overview
  buf.write_string("## API Overview\n\n")
  buf.write_string("| Package | Description |\n")
  buf.write_string("|---------|-------------|\n")
  for pkg in analysis.packages {
    if pkg.total_pub > 0 {
      buf.write_string("| `")
      buf.write_string(pkg.path)
      buf.write_string("` | ")
      buf.write_string(pkg.total_pub.to_string())
      buf.write_string(" exports |\n")
    }
  }
  buf.write_string("\n")

  // Documentation
  buf.write_string("## Documentation\n\n")
  buf.write_string("See [API Documentation](docs/) for detailed usage.\n\n")

  // License
  buf.write_string("## License\n\n")
  buf.write_string("This project is licensed under the ")
  buf.write_string(if info.license.length() > 0 { info.license } else { "MIT" })
  buf.write_string(" License - see the [LICENSE](LICENSE) file for details.\n")

  buf.to_string()
}

///|
fn extract_package_from_path(path : String) -> String {
  let chars = path.to_array()
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last_slash = i
    }
  }
  if last_slash > 0 {
    let result : Array[Char] = []
    for i = 0; i < last_slash; i = i + 1 {
      if chars[i] == '/' {
        result.push('.')
      } else {
        result.push(chars[i])
      }
    }
    String::from_array(result)
  } else {
    "pkg"
  }
}

// use @common (SoT) — format_percent
