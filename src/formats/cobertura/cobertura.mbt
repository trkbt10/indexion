///|
/// Cobertura coverage.xml writer.
///
/// Produces XML that matches the structure expected by tools wired to the
/// Cobertura DTD (`http://cobertura.sourceforge.net/xml/coverage-04.dtd`):
/// Azure DevOps, GitLab, SonarQube, Codecov, and the Jenkins Cobertura
/// plugin all consume this layout.
///
/// ```xml
/// <coverage line-rate="…" branch-rate="…" lines-covered="…" lines-valid="…"
///           branches-covered="…" branches-valid="…" complexity="0"
///           version="0.1" timestamp="…">
///   <sources>
///     <source>{source_root}</source>
///   </sources>
///   <packages>
///     <package name="…" line-rate="…" branch-rate="…" complexity="0">
///       <classes>
///         <class name="…" filename="…" line-rate="…" branch-rate="…" complexity="0">
///           <methods>…</methods>
///           <lines>
///             <line number="…" hits="…" branch="false"/>
///           </lines>
///         </class>
///       </classes>
///     </package>
///   </packages>
/// </coverage>
/// ```
///
/// Each file becomes one `<class>` whose `name` is derived from the file
/// stem and whose `filename` is the (already-relative) `FileCoverage.path`.
/// Files that share the same `pkg` field are grouped into one
/// `<package>` element. Files with an empty `pkg` land in a synthetic
/// package whose name is the literal string `"(default)"` so downstream
/// tools never see an empty `name=""` attribute (which some consumers
/// reject).
///
/// All escaping, attribute quoting, and tree-shape correctness is the
/// responsibility of `@xml`. This file is purely a *mapping* from the
/// coverage IR onto an `XmlElement` tree.

///|
/// Render a @coverage.CoverageReport as a Cobertura coverage.xml string.
pub fn render_cobertura(report : @coverage.CoverageReport) -> String {
  let opts : @xml.XmlDocumentOptions = {
    declaration: "<?xml version=\"1.0\" ?>",
    doctype: "coverage SYSTEM \"http://cobertura.sourceforge.net/xml/coverage-04.dtd\"",
    indent: "  ",
    newline: "\n",
  }
  @xml.render_document(coverage_element(report), options=opts)
}

///|
/// Build the `<coverage>` root element.
fn coverage_element(report : @coverage.CoverageReport) -> @xml.XmlElement {
  let totals = report.totals()
  let line_rate = @coverage.coverage_rate(totals.lines_hit, totals.lines_found)
  let branch_rate = @coverage.coverage_rate(
    totals.branches_hit,
    totals.branches_found,
  )
  @xml.element(
    "coverage",
    attributes=[
      @xml.attr("line-rate", format_rate(line_rate)),
      @xml.attr("branch-rate", format_rate(branch_rate)),
      @xml.attr("lines-covered", totals.lines_hit.to_string()),
      @xml.attr("lines-valid", totals.lines_found.to_string()),
      @xml.attr("branches-covered", totals.branches_hit.to_string()),
      @xml.attr("branches-valid", totals.branches_found.to_string()),
      @xml.attr("complexity", "0"),
      @xml.attr("version", "0.1"),
      @xml.attr("timestamp", report.timestamp.to_string()),
    ],
    children=[
      @xml.node_element(sources_element(report.source_root)),
      @xml.node_element(packages_element(report.files)),
    ],
  )
}

///|
fn sources_element(source_root : String) -> @xml.XmlElement {
  @xml.element("sources", children=[
    @xml.node_element(
      @xml.element("source", children=[@xml.node_text(source_root)]),
    ),
  ])
}

///|
fn packages_element(files : Array[@coverage.FileCoverage]) -> @xml.XmlElement {
  let by_package = group_files_by_package(files)
  let pkg_children : Array[@xml.XmlNode] = []
  for entry in by_package {
    pkg_children.push(@xml.node_element(package_element(entry.0, entry.1)))
  }
  @xml.element("packages", children=pkg_children)
}

///|
fn package_element(
  name : String,
  files : Array[@coverage.FileCoverage],
) -> @xml.XmlElement {
  let totals = @coverage.aggregate_totals(files)
  let line_rate = @coverage.coverage_rate(totals.lines_hit, totals.lines_found)
  let branch_rate = @coverage.coverage_rate(
    totals.branches_hit,
    totals.branches_found,
  )
  let class_children : Array[@xml.XmlNode] = []
  for file in files {
    class_children.push(@xml.node_element(class_element(file)))
  }
  @xml.element(
    "package",
    attributes=[
      @xml.attr("name", name),
      @xml.attr("line-rate", format_rate(line_rate)),
      @xml.attr("branch-rate", format_rate(branch_rate)),
      @xml.attr("complexity", "0"),
    ],
    children=[
      @xml.node_element(@xml.element("classes", children=class_children)),
    ],
  )
}

///|
fn class_element(file : @coverage.FileCoverage) -> @xml.XmlElement {
  let totals = file.totals()
  let line_rate = @coverage.coverage_rate(totals.lines_hit, totals.lines_found)
  let branch_rate = @coverage.coverage_rate(
    totals.branches_hit,
    totals.branches_found,
  )
  @xml.element(
    "class",
    attributes=[
      @xml.attr("name", class_name_from_path(file.path)),
      @xml.attr("filename", file.path),
      @xml.attr("line-rate", format_rate(line_rate)),
      @xml.attr("branch-rate", format_rate(branch_rate)),
      @xml.attr("complexity", "0"),
    ],
    children=[
      @xml.node_element(methods_element(file.functions)),
      @xml.node_element(lines_element(file.lines, file.branches)),
    ],
  )
}

///|
fn methods_element(functions : Array[@coverage.FunctionHit]) -> @xml.XmlElement {
  if functions.length() == 0 {
    return @xml.element("methods")
  }
  let funcs = @coverage.sort_functions(functions)
  let children : Array[@xml.XmlNode] = []
  for f in funcs {
    let rate = if f.hits > 0 { 1.0 } else { 0.0 }
    let method_lines = @xml.element("lines", children=[
      @xml.node_element(
        @xml.element("line", attributes=[
          @xml.attr("number", f.line.to_string()),
          @xml.attr("hits", f.hits.to_string()),
          @xml.attr("branch", "false"),
        ]),
      ),
    ])
    children.push(
      @xml.node_element(
        @xml.element(
          "method",
          attributes=[
            @xml.attr("name", f.name),
            @xml.attr("signature", "()V"),
            @xml.attr("line-rate", format_rate(rate)),
            @xml.attr("branch-rate", "1"),
          ],
          children=[@xml.node_element(method_lines)],
        ),
      ),
    )
  }
  @xml.element("methods", children~)
}

///|
fn lines_element(
  lines : Array[@coverage.LineHit],
  branches : Array[@coverage.BranchHit],
) -> @xml.XmlElement {
  if lines.length() == 0 {
    return @xml.element("lines")
  }
  let branches_by_line = group_branches_by_line(branches)
  let sorted = @coverage.sort_lines(lines)
  let children : Array[@xml.XmlNode] = []
  for l in sorted {
    children.push(
      @xml.node_element(line_element(l, branches_by_line.get(l.line))),
    )
  }
  @xml.element("lines", children~)
}

///|
fn line_element(
  l : @coverage.LineHit,
  line_branches : Array[@coverage.BranchHit]?,
) -> @xml.XmlElement {
  let attrs : Array[@xml.XmlAttr] = [
    @xml.attr("number", l.line.to_string()),
    @xml.attr("hits", l.hits.to_string()),
  ]
  match line_branches {
    Some(arr) =>
      if arr.length() > 0 {
        let mut taken = 0
        for b in arr {
          if b.taken > 0 {
            taken = taken + 1
          }
        }
        let total = arr.length()
        let pct = (taken.to_double() / total.to_double() * 100.0 + 0.5).to_int()
        attrs.push(@xml.attr("branch", "true"))
        attrs.push(
          @xml.attr(
            "condition-coverage",
            pct.to_string() +
            "% (" +
            taken.to_string() +
            "/" +
            total.to_string() +
            ")",
          ),
        )
      } else {
        attrs.push(@xml.attr("branch", "false"))
      }
    None => attrs.push(@xml.attr("branch", "false"))
  }
  @xml.element("line", attributes=attrs)
}

///|
/// Group files by their `pkg` field, preserving first-seen order. Files
/// with empty package land in `"(default)"` so the XML never emits `name=""`.
fn group_files_by_package(
  files : Array[@coverage.FileCoverage],
) -> Array[(String, Array[@coverage.FileCoverage])] {
  let order : Array[String] = []
  let groups : Map[String, Array[@coverage.FileCoverage]] = {}
  for file in files {
    let key = if file.pkg.length() > 0 { file.pkg } else { "(default)" }
    match groups.get(key) {
      Some(arr) => arr.push(file)
      None => {
        groups.set(key, [file])
        order.push(key)
      }
    }
  }
  let result : Array[(String, Array[@coverage.FileCoverage])] = []
  for k in order {
    match groups.get(k) {
      Some(arr) => result.push((k, arr))
      None => ()
    }
  }
  result
}

///|
fn group_branches_by_line(
  branches : Array[@coverage.BranchHit],
) -> Map[Int, Array[@coverage.BranchHit]] {
  let map : Map[Int, Array[@coverage.BranchHit]] = {}
  for b in branches {
    match map.get(b.line) {
      Some(arr) => arr.push(b)
      None => map.set(b.line, [b])
    }
  }
  map
}

// aggregate_totals, sort_functions, sort_lines: use @coverage (types.mbt) SoT.

///|
/// Derive a `<class name=...>` value from a file path. The class name is
/// purely cosmetic in Cobertura output (the `filename` attribute is what
/// tools use for source lookup), but a meaningful value helps when
/// browsing reports. We use the basename without extension.
fn class_name_from_path(path : String) -> String {
  let chars = path.to_array()
  let mut last_sep = -1
  let mut last_dot = -1
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c == '/' || c == '\\' {
      last_sep = i
      last_dot = -1
    } else if c == '.' {
      last_dot = i
    }
  }
  let start = last_sep + 1
  let end = if last_dot > last_sep { last_dot } else { chars.length() }
  if start >= end {
    return path
  }
  let out : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    out.push(chars[i])
  }
  String::from_array(out)
}

///|
/// Format a coverage rate (0.0..1.0) as the fixed-point string Cobertura
/// consumers expect — 4 fractional digits, e.g. `0.0000`, `0.8333`,
/// `1.0000`. We avoid `Double::to_string()` because its scientific
/// notation breaks the DTD's numeric pattern.
fn format_rate(rate : Double) -> String {
  let clamped = if rate < 0.0 { 0.0 } else if rate > 1.0 { 1.0 } else { rate }
  // Scale to 10000 and round to nearest integer, then format manually.
  let scaled = (clamped * 10000.0 + 0.5).to_int()
  let int_part = scaled / 10000
  let frac_part = scaled % 10000
  let frac_str = pad_left(frac_part.to_string(), 4, '0')
  int_part.to_string() + "." + frac_str
}

///|
/// Left-pad a string with `pad` until it reaches `width`. If the input is
/// already at least `width` characters it is returned unchanged.
fn pad_left(s : String, width : Int, pad : Char) -> String {
  let len = s.to_array().length()
  if len >= width {
    return s
  }
  let buf = StringBuilder::new()
  for _ in 0..<(width - len) {
    buf.write_char(pad)
  }
  buf.write_string(s)
  buf.to_string()
}
