///|
/// # indexion plan wiki
///
/// Analyze project structure and generate a wiki writing plan.
/// Proposes concept-based page structure and writing tasks for agents.
///
/// If .indexion/wiki/ already exists, detects pages that need updates
/// based on source file changes.

///|
pub struct WikiPlanConfig {
  target_dir : String
  output : String
  format : String
  specs_dir : String
  wiki_dir : String
}

///|
pub fn WikiPlanConfig::from_matches(
  matches : @argparse.Matches,
) -> WikiPlanConfig {
  let output = match matches.values.get("output") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let format = match matches.values.get("format") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "md" }
    _ => "md"
  }
  let specs_dir = match matches.values.get("specs-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "kgfs" }
    _ => "kgfs"
  }
  let wiki_dir = match matches.values.get("wiki-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { ".indexion/wiki" }
    _ => ".indexion/wiki"
  }
  let target_dir = match matches.values.get("directory") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "." }
    _ => "."
  }
  { target_dir, output, format, specs_dir, wiki_dir }
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "plan",
    about="Generate wiki writing plan from project analysis",
    options=[
      @argparse.OptionArg("output", short='o', about=@help.output),
      @argparse.OptionArg(
        "format",
        about="Output format: md, json, github-issue",
        default_values=["md"],
      ),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
      @argparse.OptionArg("wiki-dir", about="Wiki directory", default_values=[
        ".indexion/wiki",
      ]),
    ],
    positionals=[
      @argparse.PositionArg(
        "directory",
        about="Project root directory",
        num_args=@argparse.ValueRange(lower=0, upper=1),
      ),
    ],
  )
}

///|
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let parsed = WikiPlanConfig::from_matches(matches)
  let config = {
    ..parsed,
    wiki_dir: if parsed.wiki_dir == ".indexion/wiki" {
      match @config.resolve_project_indexion_dir(parsed.target_dir, "wiki") {
        Some(dir) => dir
        None => {
          println("Error: Could not find project root directory.")
          return
        }
      }
    } else {
      parsed.wiki_dir
    },
  }
  println("Analyzing project structure...")
  let graph = match
    @digest_cli.build_graph_from_source(config.target_dir, config.specs_dir) {
    Some(r) => r.graph
    None => {
      println("Failed to build project graph.")
      return
    }
  }
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dir=config.target_dir,
  )
  let existing_wiki = @wiki_reader.load_wiki(config.wiki_dir, registry~)
  let plan = analyze_and_plan(graph, existing_wiki, config)
  let output_content = match config.format {
    "json" => plan.to_json().stringify(indent=2)
    "github-issue" => @plan_render.render_github_issue(plan).format()
    _ => @plan_render.render_markdown(plan)
  }
  @common.write_output(config.output, output_content, label="Wiki plan")
}

///|
fn analyze_and_plan(
  graph : @graph.CodeGraph,
  existing : @wiki_types.WikiData?,
  _config : WikiPlanConfig,
) -> @plan_types.PlanDocument {
  let doc = @plan_types.PlanDocument::new("Wiki Documentation Plan")
  doc.set_description(
    "Concept-based wiki page structure and writing tasks for the project.",
  )
  doc.set_meta("labels", "documentation,wiki")
  // 1. Project summary
  doc.add_section(build_summary_section(graph))
  // 2. Proposed page structure
  doc.add_section(propose_page_structure(graph))
  // 3. Writing tasks
  doc.add_section(build_writing_tasks(graph, existing))
  // 4. Update tasks (if wiki exists)
  match existing {
    Some(wiki) => {
      let updates = detect_update_needs(wiki)
      match updates.content {
        @plan_types.Checklist(items) =>
          if items.length() > 0 {
            doc.add_section(updates)
          }
        _ => ()
      }
    }
    None => ()
  }
  doc
}

// --- Sections ---

///|
fn build_summary_section(graph : @graph.CodeGraph) -> @plan_types.PlanSection {
  let items : Array[@plan_types.ListItem] = []
  items.push(
    @plan_types.ListItem::simple("Modules: " + graph.module_count().to_string()),
  )
  items.push(
    @plan_types.ListItem::simple("Symbols: " + graph.symbol_count().to_string()),
  )
  items.push(
    @plan_types.ListItem::simple("Edges: " + graph.edge_count().to_string()),
  )
  let mut internal = 0
  let top_dirs : Map[String, Bool] = {}
  for entry in graph.get_modules() {
    match entry.1.file {
      Some(_) => {
        internal = internal + 1
        let dir = @common.parent_dir(entry.0)
        if dir.length() > 0 && dir != "." {
          let parts = @common.split_by_slash(dir)
          if parts.length() > 0 {
            top_dirs[parts[0]] = true
          }
        }
      }
      None => ()
    }
  }
  items.push(
    @plan_types.ListItem::simple("Internal modules: " + internal.to_string()),
  )
  let dir_names : Array[String] = []
  for entry in top_dirs {
    dir_names.push(entry.0)
  }
  items.push(
    @plan_types.ListItem::simple(
      "Top-level directories: " + dir_names.join(", "),
    ),
  )
  @plan_types.PlanSection::new(
    "summary",
    "Project Summary",
    @plan_types.SectionContent::list(items),
  )
}

///|
fn propose_page_structure(graph : @graph.CodeGraph) -> @plan_types.PlanSection {
  let items : Array[@plan_types.ListItem] = []
  items.push(
    @plan_types.ListItem::with_desc(
      "Overview", "Project purpose, architecture overview, getting started links",
    ),
  )
  items.push(
    @plan_types.ListItem::with_desc(
      "Getting Started", "Installation, project setup, first commands",
    ),
  )
  items.push(
    @plan_types.ListItem::with_desc(
      "Core Concepts", "Key abstractions and how they relate (data flow diagrams)",
    ),
  )
  items.push(
    @plan_types.ListItem::with_desc(
      "Architecture", "Layered architecture, package organization, extension points",
    ),
  )
  // Cluster-specific pages from module structure
  let clusters = collect_clusters(graph)
  for entry in clusters {
    let cluster = entry.0
    let module_count = entry.1
    let decl_count = count_cluster_declarations(graph, cluster)
    items.push(
      @plan_types.ListItem::with_desc(
        cluster,
        module_count.to_string() +
        " modules, " +
        decl_count.to_string() +
        " declarations",
      ),
    )
  }
  @plan_types.PlanSection::new(
    "structure",
    "Proposed Page Structure",
    @plan_types.SectionContent::list(items),
  )
}

///|
fn build_writing_tasks(
  graph : @graph.CodeGraph,
  existing : @wiki_types.WikiData?,
) -> @plan_types.PlanSection {
  let items : Array[@plan_types.ChecklistItem] = []
  let existing_pages : Map[String, Bool] = {}
  match existing {
    Some(wiki) =>
      for entry in wiki.pages {
        existing_pages[entry.0] = true
      }
    None => ()
  }
  // Core pages
  let core = [
    (
      "overview", "Overview — project purpose, architecture diagram, key concepts",
    ),
    (
      "getting-started", "Getting Started — installation, setup, first commands",
    ),
    (
      "core-concepts", "Core Concepts — key abstractions, data flow, concept map",
    ),
    ("architecture", "Architecture — layers, package org, extension points"),
  ]
  for pair in core {
    let (id, desc) = pair
    if existing_pages.contains(id) {
      items.push(
        @plan_types.ChecklistItem::with_desc(
          desc, "Exists — review for accuracy",
        ),
      )
    } else {
      items.push(@plan_types.ChecklistItem::with_priority(desc, 1))
    }
  }
  // Cluster pages
  let clusters = collect_clusters(graph)
  for entry in clusters {
    let cluster = entry.0
    let module_count = entry.1
    let slug = @common.slugify(cluster)
    let label = cluster + " (" + module_count.to_string() + " modules)"
    if existing_pages.contains(slug) {
      items.push(
        @plan_types.ChecklistItem::with_desc(
          label, "Exists — review for accuracy",
        ),
      )
    } else {
      items.push(@plan_types.ChecklistItem::with_priority(label, 2))
    }
  }
  @plan_types.PlanSection::new(
    "tasks",
    "Writing Tasks",
    @plan_types.SectionContent::checklist(items),
  )
}

///|
fn detect_update_needs(wiki : @wiki_types.WikiData) -> @plan_types.PlanSection {
  let items : Array[@plan_types.ChecklistItem] = []
  for entry in wiki.pages {
    let page = entry.1
    let mut missing = 0
    for src in page.sources {
      if !@fs.path_exists(src.file) {
        missing = missing + 1
      }
    }
    if missing > 0 {
      items.push(
        @plan_types.ChecklistItem::with_priority(
          "Update: " +
          page.title +
          " — " +
          missing.to_string() +
          " source(s) missing",
          1,
        ),
      )
    }
  }
  @plan_types.PlanSection::new(
    "updates",
    "Pages Needing Update",
    @plan_types.SectionContent::checklist(items),
  )
}

// --- Helpers ---

///|
fn collect_clusters(graph : @graph.CodeGraph) -> Map[String, Int] {
  let clusters : Map[String, Int] = {}
  for entry in graph.get_modules() {
    match entry.1.file {
      None => continue
      Some(_) => ()
    }
    let dir = @common.parent_dir(entry.0)
    if dir.length() == 0 || dir == "." {
      continue
    }
    let parts = @common.split_by_slash(dir)
    let key = if parts.length() >= 2 {
      parts[0] + "/" + parts[1]
    } else {
      parts[0]
    }
    let count = match clusters.get(key) {
      Some(c) => c
      None => 0
    }
    clusters[key] = count + 1
  }
  clusters
}

///|
fn count_cluster_declarations(
  graph : @graph.CodeGraph,
  cluster_key : String,
) -> Int {
  let mut count = 0
  for entry in graph.get_modules() {
    match entry.1.file {
      None => continue
      Some(_) => ()
    }
    let dir = @common.parent_dir(entry.0)
    if dir.length() == 0 || dir == "." {
      continue
    }
    let parts = @common.split_by_slash(dir)
    let key = if parts.length() >= 2 {
      parts[0] + "/" + parts[1]
    } else {
      parts[0]
    }
    if key == cluster_key {
      count = count + @query.get_module_declarations(graph, entry.0).length()
    }
  }
  count
}
