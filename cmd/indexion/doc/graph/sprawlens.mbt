///|
/// Render a `CodeGraph` as a sprawlens `Snapshot` JSON.
///
/// This intentionally writes the format sprawlens already consumes instead of
/// asking sprawlens to understand indexion's `codegraph` JSON.

///|
priv struct FileStats {
  loc : Int
  size_bytes : Int
  line_starts : Array[Int]
}

///|
fn slash_path(path : String) -> String {
  let buf = StringBuilder::new()
  for ch in path.to_array() {
    if ch == '\\' {
      buf.write_char('/')
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
fn dirname(path : String) -> String {
  @config.dirname(path)
}

///|
fn basename(path : String) -> String {
  @config.basename(path)
}

///|
fn normalize_repo_root(root_dir : String) -> String {
  let is_file = @fs.is_file(root_dir) catch { _ => false }
  if is_file {
    dirname(root_dir)
  } else {
    root_dir
  }
}

///|
fn absolute_repo_root(root_dir : String) -> String {
  let root = normalize_repo_root(root_dir)
  if @config.is_absolute_path(root) {
    @config.normalize_path(root)
  } else {
    match @env.current_dir() {
      Some(cwd) => @config.resolve_path(cwd, root)
      None => @config.normalize_path(root)
    }
  }
}

///|
fn snapshot_path(root_dir : String, path : String) -> String {
  let normalized_root = @config.normalize_path(root_dir)
  let normalized_path = @config.normalize_path(path)
  let relative = @config.relative_to(normalized_root, normalized_path)
  if relative == ".." || relative.has_prefix("../") {
    slash_path(normalized_path)
  } else {
    slash_path(relative)
  }
}

///|
fn file_stats_from_content(content : String) -> FileStats {
  let starts : Array[Int] = [0]
  let mut i = 0
  while i < content.length() {
    let ch = content[i].to_int().unsafe_to_char()
    if ch == '\n' {
      starts.push(i + 1)
    }
    i = i + 1
  }
  {
    loc: if content.length() == 0 {
      1
    } else {
      starts.length()
    },
    size_bytes: @utf8.encode(content).length(),
    line_starts: starts,
  }
}

///|
fn read_file_stats(path : String) -> FileStats {
  let content = @fs.read_file_to_string(path) catch { _ => "" }
  file_stats_from_content(content)
}

///|
fn offset_from_id(id : String) -> Int? {
  let chars = id.to_array()
  let mut at = -1
  for i, ch in chars {
    if ch == '@' {
      at = i
    }
  }
  if at < 0 || at + 1 >= chars.length() {
    return None
  }
  let buf = StringBuilder::new()
  for i = at + 1; i < chars.length(); i = i + 1 {
    let ch = chars[i]
    if ch < '0' || ch > '9' {
      return None
    }
    buf.write_char(ch)
  }
  let parsed = @string.parse_int(buf.to_string()) catch { _ => return None }
  Some(parsed)
}

///|
fn line_from_id(id : String, stats : FileStats) -> Int {
  match offset_from_id(id) {
    Some(offset) => {
      let mut line = 1
      for i, start in stats.line_starts {
        if start > offset {
          break
        }
        line = i + 1
      }
      line
    }
    None => 1
  }
}

///|
fn display_name_from_id(id : String) -> String {
  let chars = id.to_array()
  let mut sep = -1
  for i = 1; i < chars.length(); i = i + 1 {
    if chars[i - 1] == ':' && chars[i] == ':' {
      sep = i
    }
  }
  if sep >= 0 && sep + 1 < chars.length() {
    @config.substring_from(id, sep + 1)
  } else {
    basename(id)
  }
}

///|
fn sprawlens_symbol_kind(kind : String) -> String {
  match kind {
    "function" | "Function" | "fn" | "Func" => "function"
    "class" | "Class" | "struct" | "Struct" | "record" => "class"
    "interface" | "Interface" | "trait" | "Trait" => "interface"
    "enum" | "Enum" => "enum"
    "type" | "Type" => "type"
    "macro" | "Macro" => "macro"
    "method" | "Method" => "method"
    "property" | "Property" | "field" | "Field" => "property"
    "Heading" | "heading" | "Section" | "section" | "Chapter" | "chapter" =>
      "type"
    _ => "variable"
  }
}

///|
fn symbol_json(
  id : String,
  name : String,
  kind : String,
  stats : FileStats,
) -> Json {
  let line = line_from_id(id, stats)
  {
    "id": id.to_json(),
    "kind": sprawlens_symbol_kind(kind).to_json(),
    "name": name.to_json(),
    "startLine": line.to_json(),
    "endLine": line.to_json(),
    "loc": (1).to_json(),
    "complexity": (1).to_json(),
    "exported": false.to_json(),
  }
}

///|
fn ensure_symbol_json(
  symbols_by_file : Map[String, Array[Json]],
  symbol_to_file : Map[String, String],
  seen_symbols : Map[String, Bool],
  file_path : String,
  id : String,
  name : String,
  kind : String,
  stats : FileStats,
) -> Unit {
  if seen_symbols.contains(id) {
    return
  }
  seen_symbols.set(id, true)
  symbol_to_file.set(id, file_path)
  let arr = match symbols_by_file.get(file_path) {
    Some(existing) => existing
    None => {
      let created : Array[Json] = []
      symbols_by_file.set(file_path, created)
      created
    }
  }
  arr.push(symbol_json(id, name, kind, stats))
}

///|
fn metrics_json(nodes : Array[Json], edges : Array[Json]) -> Json {
  let mut loc = 0
  let mut file_count = 0
  let mut dir_count = 0
  let mut import_count = 0
  let fan_in : Map[String, Int] = {}
  let fan_out : Map[String, Int] = {}
  for node in nodes {
    guard node is { "type": String(node_type), .. } else { continue }
    if node_type == "file" {
      file_count = file_count + 1
      match node {
        { "loc": Number(n, ..), "id": String(id), .. } => {
          loc = loc + n.to_int()
          fan_in.set(id, 0)
          fan_out.set(id, 0)
        }
        _ => ()
      }
    } else if node_type == "dir" {
      dir_count = dir_count + 1
    }
  }
  for edge in edges {
    guard edge
      is {
        "type": String(edge_type),
        "from": String(from),
        "to": String(to),
        ..
      } else {
      continue
    }
    if edge_type == "imports" {
      import_count = import_count + 1
      fan_out.set(from, fan_out.get(from).unwrap_or(0) + 1)
      fan_in.set(to, fan_in.get(to).unwrap_or(0) + 1)
    }
  }
  let mut max_fan_in = 0
  for _, v in fan_in {
    if v > max_fan_in {
      max_fan_in = v
    }
  }
  let mut max_fan_out = 0
  for _, v in fan_out {
    if v > max_fan_out {
      max_fan_out = v
    }
  }
  {
    "loc": loc.to_json(),
    "fileCount": file_count.to_json(),
    "dirCount": dir_count.to_json(),
    "importEdgeCount": import_count.to_json(),
    "unresolvedImportCount": (0).to_json(),
    "cycleCount": (0).to_json(),
    "largestComponentSize": file_count.to_json(),
    "maxFanIn": max_fan_in.to_json(),
    "maxFanOut": max_fan_out.to_json(),
  }
}

///|
fn contains_edge_json(from : String, to : String) -> Json {
  {
    "id": ("contains:" + from + "->" + to).to_json(),
    "type": "contains".to_json(),
    "from": from.to_json(),
    "to": to.to_json(),
  }
}

///|
fn import_edge_json(
  index : Int,
  from_file : String,
  to_file : String,
  specifier : String,
  from_symbol_id? : String? = None,
  to_symbol_id? : String? = None,
) -> Json {
  let obj : Map[String, Json] = {
    "id": ("imports:" + index.to_string()).to_json(),
    "type": "imports".to_json(),
    "from": ("file:" + from_file).to_json(),
    "to": ("file:" + to_file).to_json(),
    "specifier": specifier.to_json(),
    "resolved": true.to_json(),
  }
  match to_symbol_id {
    Some(to_id) => {
      let imported = specifier
      let sym : Map[String, Json] = {
        "imported": imported.to_json(),
        "local": imported.to_json(),
        "kind": "named".to_json(),
        "toSymbolId": to_id.to_json(),
      }
      match from_symbol_id {
        Some(from_id) => sym.set("fromSymbolId", from_id.to_json())
        None => ()
      }
      obj.set("symbolImports", Json::array([Json::object(sym)]))
    }
    None => ()
  }
  Json::object(obj)
}

///|
fn render_sprawlens_snapshot(
  graph : @core_graph.CodeGraph,
  files : Array[(String, String)],
  root_dir : String,
  title : String,
) -> String {
  let repo_root = absolute_repo_root(root_dir)
  let module_to_file : Map[String, String] = {}
  let file_stats : Map[String, FileStats] = {}
  for file in files {
    let rel = snapshot_path(repo_root, file.0)
    file_stats.set(rel, file_stats_from_content(file.1))
  }
  for id, mod_node in graph.get_modules() {
    match mod_node.file {
      Some(path) => {
        let rel = snapshot_path(repo_root, path)
        module_to_file.set(id, rel)
        if !file_stats.contains(rel) {
          file_stats.set(rel, read_file_stats(path))
        }
      }
      None => ()
    }
  }

  let symbols_by_file : Map[String, Array[Json]] = {}
  let symbol_to_file : Map[String, String] = {}
  let seen_symbols : Map[String, Bool] = {}
  for id, symbol in graph.get_symbols() {
    match module_to_file.get(symbol.module_id) {
      Some(file_path) => {
        let stats = file_stats
          .get(file_path)
          .unwrap_or(FileStats::{ loc: 1, size_bytes: 0, line_starts: [0] })
        ensure_symbol_json(
          symbols_by_file,
          symbol_to_file,
          seen_symbols,
          file_path,
          id,
          symbol.name,
          symbol.kind,
          stats,
        )
      }
      None => ()
    }
  }
  for edge in graph.get_edges() {
    if !(edge.kind is @core_graph.Declares) {
      continue
    }
    match module_to_file.get(edge.from) {
      Some(file_path) => {
        let stats = file_stats
          .get(file_path)
          .unwrap_or(FileStats::{ loc: 1, size_bytes: 0, line_starts: [0] })
        let name = edge.attrs
          .get("name")
          .unwrap_or(display_name_from_id(edge.to))
        let kind = edge.attrs.get("kind").unwrap_or("variable")
        ensure_symbol_json(
          symbols_by_file,
          symbol_to_file,
          seen_symbols,
          file_path,
          edge.to,
          name,
          kind,
          stats,
        )
      }
      None => ()
    }
  }

  let dirs : Map[String, Bool] = {}
  for _, file_path in module_to_file {
    let mut dir = dirname(file_path)
    while dir.length() > 0 && dir != "." {
      dirs.set(dir, true)
      dir = dirname(dir)
    }
  }
  let dir_paths : Array[String] = []
  for dir, _ in dirs {
    dir_paths.push(dir)
  }
  dir_paths.sort()
  let file_paths : Array[String] = []
  for _, file_path in module_to_file {
    file_paths.push(file_path)
  }
  file_paths.sort()

  let nodes : Array[Json] = []
  nodes.push({
    "id": "repo".to_json(),
    "type": "repo".to_json(),
    "name": basename(repo_root).to_json(),
  })
  for dir in dir_paths {
    nodes.push({
      "id": ("dir:" + dir).to_json(),
      "type": "dir".to_json(),
      "path": dir.to_json(),
    })
  }
  for file_path in file_paths {
    let stats = file_stats
      .get(file_path)
      .unwrap_or(FileStats::{ loc: 1, size_bytes: 0, line_starts: [0] })
    nodes.push({
      "id": ("file:" + file_path).to_json(),
      "type": "file".to_json(),
      "path": file_path.to_json(),
      "ext": @config.extension(file_path).to_json(),
      "loc": stats.loc.to_json(),
      "sizeBytes": stats.size_bytes.to_json(),
      "symbols": Json::array(symbols_by_file.get(file_path).unwrap_or([])),
    })
  }

  let edges : Array[Json] = []
  for dir in dir_paths {
    let parent = dirname(dir)
    edges.push(
      contains_edge_json(
        if parent.length() == 0 || parent == "." {
          "repo"
        } else {
          "dir:" + parent
        },
        "dir:" + dir,
      ),
    )
  }
  for file_path in file_paths {
    let parent = dirname(file_path)
    edges.push(
      contains_edge_json(
        if parent.length() == 0 || parent == "." {
          "repo"
        } else {
          "dir:" + parent
        },
        "file:" + file_path,
      ),
    )
  }

  let seen_imports : Map[String, Bool] = {}
  let mut edge_index = 0
  for edge in graph.get_edges() {
    if edge.kind is @core_graph.Declares ||
      edge.kind is @core_graph.Custom("contains") {
      continue
    }
    let from_file = match module_to_file.get(edge.from) {
      Some(path) => Some(path)
      None => symbol_to_file.get(edge.from)
    }
    let to_file = match module_to_file.get(edge.to) {
      Some(path) => Some(path)
      None => symbol_to_file.get(edge.to)
    }
    match (from_file, to_file) {
      (Some(from_path), Some(to_path)) => {
        let from_symbol_id = if symbol_to_file.contains(edge.from) {
          Some(edge.from)
        } else {
          None
        }
        let to_symbol_id = if symbol_to_file.contains(edge.to) {
          Some(edge.to)
        } else {
          None
        }
        let specifier = edge.kind.to_string()
        let key = from_path +
          "\u{1f}" +
          to_path +
          "\u{1f}" +
          specifier +
          "\u{1f}" +
          from_symbol_id.unwrap_or("") +
          "\u{1f}" +
          to_symbol_id.unwrap_or("")
        if seen_imports.contains(key) {
          continue
        }
        seen_imports.set(key, true)
        edge_index = edge_index + 1
        edges.push(
          import_edge_json(
            edge_index,
            from_path,
            to_path,
            specifier,
            from_symbol_id~,
            to_symbol_id~,
          ),
        )
      }
      _ => ()
    }
  }

  let root : Map[String, Json] = {
    "schemaVersion": (1).to_json(),
    "repoPath": repo_root.to_json(),
    "commit": Json::object({
      "hash": "INDEXION".to_json(),
      "shortHash": "indexion".to_json(),
      "timestamp": "1970-01-01T00:00:00.000Z".to_json(),
      "authorName": "indexion".to_json(),
      "message": title.to_json(),
      "aiIndicators": Json::array([]),
    }),
    "nodes": Json::array(nodes),
    "edges": Json::array(edges),
    "metrics": metrics_json(nodes, edges),
  }
  Json::object(root).stringify()
}
