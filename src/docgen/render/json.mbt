// JSON rendering for documentation.

///|
/// Render complete documentation data as JSON.
pub fn render_json(graph : @graph.CodeGraph) -> String {
  // Extract all data
  let decls = @query.extract_declarations(graph)
  let deps = @query.extract_module_deps(graph)
  let calls = @query.extract_call_graph(graph)
  let hierarchy = @query.extract_type_hierarchy(graph)
  let refs = @query.extract_references(graph)
  // Build JSON object
  let obj : Map[String, Json] = {}
  // Add modules
  let modules_arr : Array[Json] = []
  for entry in graph.get_modules() {
    let m = entry.1
    let m_obj : Map[String, Json] = {}
    m_obj.set("id", m.id.to_json())
    match m.file {
      Some(f) => m_obj.set("file", f.to_json())
      None => ()
    }
    modules_arr.push(Json::object(m_obj))
  }
  obj.set("modules", Json::array(modules_arr))
  // Add symbols (declarations)
  let symbols_arr : Array[Json] = []
  for decl in decls {
    let s_obj : Map[String, Json] = {}
    s_obj.set("id", decl.id.to_json())
    s_obj.set("name", decl.name.to_json())
    s_obj.set("kind", decl.kind.to_json())
    s_obj.set("module", decl.module_id.to_json())
    match decl.doc {
      Some(d) => s_obj.set("doc", d.to_json())
      None => ()
    }
    symbols_arr.push(Json::object(s_obj))
  }
  obj.set("symbols", Json::array(symbols_arr))
  // Add dependencies
  let deps_arr : Array[Json] = []
  for dep in deps {
    let d_obj : Map[String, Json] = {}
    d_obj.set("from", dep.from.to_json())
    d_obj.set("to", dep.to.to_json())
    match dep.via {
      Some(v) => d_obj.set("via", v.to_json())
      None => ()
    }
    match dep.dep_kind {
      Some(k) => d_obj.set("dep_kind", k.to_json())
      None => ()
    }
    deps_arr.push(Json::object(d_obj))
  }
  obj.set("dependencies", Json::array(deps_arr))
  // Add calls
  let calls_arr : Array[Json] = []
  for call in calls {
    let c_obj : Map[String, Json] = {}
    c_obj.set("caller", call.caller.to_json())
    c_obj.set("callee", call.callee.to_json())
    c_obj.set("file", call.file.to_json())
    calls_arr.push(Json::object(c_obj))
  }
  obj.set("calls", Json::array(calls_arr))
  // Add type hierarchy
  let hier_arr : Array[Json] = []
  for rel in hierarchy {
    let h_obj : Map[String, Json] = {}
    h_obj.set("child", rel.child.to_json())
    h_obj.set("parent", rel.parent.to_json())
    h_obj.set("relation", rel.relation.to_json())
    hier_arr.push(Json::object(h_obj))
  }
  obj.set("hierarchy", Json::array(hier_arr))
  // Add references
  let refs_arr : Array[Json] = []
  for ref_ in refs {
    let r_obj : Map[String, Json] = {}
    r_obj.set("symbol", ref_.symbol.to_json())
    r_obj.set("site", ref_.ref_site.to_json())
    r_obj.set("kind", ref_.ref_kind.to_json())
    refs_arr.push(Json::object(r_obj))
  }
  obj.set("references", Json::array(refs_arr))
  Json::object(obj).stringify()
}

///|
/// Render graph structure as JSON (simplified).
pub fn render_graph_json(graph : @graph.CodeGraph) -> String {
  graph.to_json_string()
}
