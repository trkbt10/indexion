///|
/// White-box tests for lift + lower halves of the engine.

///|
fn make_lift(
  scalars : Map[String, String],
  type_wraps : Array[TypeWrap],
  rule_lifts : Map[String, String],
) -> LiftSpec {
  {
    scalars,
    type_wraps,
    rule_lifts,
    structural_rules: None,
    module_aliases: None,
    symbol_aliases: None,
    body_delimiters: None,
    regex_replace: None,
  }
}

///|
fn make_lower(
  scalars : Map[String, String],
  type_wraps : Array[TypeWrap],
  emit_templates : Map[String, String],
  emit_order : Array[String],
) -> LowerSpec {
  {
    scalars,
    type_wraps,
    emit_templates,
    emit_order,
    comment_prefix: "// ",
    preamble_template: "{{comment_prefix}}gen {{source_lang}} -> {{target_lang}}\n",
    no_template_template: "{{comment_prefix}}{{unresolved_marker}}no_template:{{rule}}\n",
    default_body: None,
    text_replace: None,
    text_replace_pairs: None,
    regex_replace: None,
    collect_separators: None,
    module_aliases: None,
    symbol_aliases: None,
    variant_case_style: None,
  }
}

///|
test "lift: rule rename + scalar in label _text" {
  let scalars : Map[String, String] = {}
  scalars.set("number", "Float")
  let renames : Map[String, String] = {}
  renames.set("PropertySig", "IRStructField")
  let lift = make_lift(scalars, [], renames)
  let labels : Map[String, Json] = {}
  labels.set("id_text", "id".to_json())
  labels.set("_text", "id:number;".to_json())
  let lifted = lift_events([("PropertySig", labels)], lift)
  inspect(lifted[0].0, content="IRStructField")
  match lifted[0].1.get("_text") {
    Some(String(s)) => inspect(s, content="id:Float;")
    _ => abort("expected _text label")
  }
}

///|
test "lift_type_text: wraps run before scalars on isolated type fragments" {
  // type_wraps are applied only to isolated type expressions (via
  // extract_text or rewrite_type_text), NOT to composite `_text` labels
  // like `argv:string[]` — that distinction prevents cross-token mismatches.
  let scalars : Map[String, String] = {}
  scalars.set("number", "Float")
  let wraps : Array[TypeWrap] = [
    { source_suffix: "[]", target_template: "Array<%s>" },
  ]
  let lift = make_lift(scalars, wraps, Map([]))
  inspect(lift_type_text("number[]", lift), content="Array<Float>")
}

///|
test "lift_event: scalars applied broadly, wraps NOT applied to composite _text" {
  // The bug being prevented: a Param event's `_text` is `argv:string[]`.
  // If wraps fired here, the whole composite would become `Array<argv:string>`.
  let scalars : Map[String, String] = {}
  scalars.set("string", "String")
  let wraps : Array[TypeWrap] = [
    { source_suffix: "[]", target_template: "Array<%s>" },
  ]
  let lift = make_lift(scalars, wraps, Map([]))
  let labels : Map[String, Json] = {}
  labels.set("_text", "argv:string[]".to_json())
  let lifted = lift_events([("Param", labels)], lift)
  match lifted[0].1.get("_text") {
    Some(String(s)) => inspect(s, content="argv:String[]")
    _ => abort("expected _text label")
  }
}

///|
test "lower: emit_templates fill placeholders, missing → @@UNRESOLVED@@" {
  let templates : Map[String, String] = {}
  templates.set("IREnum", "pub enum {{id_text}} { {{variants}} }\n")
  let lower = make_lower(Map([]), [], templates, ["IREnum"])
  let labels : Map[String, Json] = {}
  labels.set("id_text", "TodoStatus".to_json())
  // No `variants` label — should become @@UNRESOLVED@@variants
  let lift = make_lift(Map([]), [], Map([]))
  let code = lower_to_code(
    [("IREnum", labels)],
    [],
    "src",
    "tgt",
    "@@UNRESOLVED@@",
    lift,
    lower,
  )
  // Preamble + template
  inspect(
    code.contains("pub enum TodoStatus { @@UNRESOLVED@@variants }"),
    content="true",
  )
}

///|
test "lower: rule outside emit_order is skipped" {
  let templates : Map[String, String] = {}
  templates.set("IREnum", "ENUM:{{id_text}}\n")
  let lower = make_lower(Map([]), [], templates, ["IREnum"])
  let labels : Map[String, Json] = {}
  labels.set("id_text", "X".to_json())
  let lift = make_lift(Map([]), [], Map([]))
  let code = lower_to_code(
    [("Item", labels), ("IREnum", labels)],
    [],
    "src",
    "tgt",
    "@@UNRESOLVED@@",
    lift,
    lower,
  )
  inspect(code.contains("ENUM:X"), content="true")
  inspect(code.contains("Item"), content="false")
}

///|
test "module_alias: node:fs → fs → @fs end-to-end" {
  // Demonstrates user-extensible library translation via spec data.
  let lift_aliases : Map[String, String] = {}
  lift_aliases.set("node:fs", "fs")
  let lift : LiftSpec = {
    scalars: Map([]),
    type_wraps: [],
    rule_lifts: { "ImportNamed": "IRImport" },
    structural_rules: None,
    module_aliases: Some(lift_aliases),
    symbol_aliases: None,
    body_delimiters: None,
    regex_replace: None,
  }
  let lower_aliases : Map[String, String] = {}
  lower_aliases.set("fs", "@fs")
  let templates : Map[String, String] = {}
  templates.set("IRImport", "use {{module_target}}\n")
  let lower : LowerSpec = {
    scalars: Map([]),
    type_wraps: [],
    emit_templates: templates,
    emit_order: ["IRImport"],
    comment_prefix: "// ",
    preamble_template: "",
    no_template_template: "",
    default_body: None,
    text_replace: None,
    text_replace_pairs: None,
    regex_replace: None,
    collect_separators: None,
    module_aliases: Some(lower_aliases),
    symbol_aliases: None,
    variant_case_style: None,
  }
  let labels : Map[String, Json] = {}
  labels.set("from_text", "node:fs".to_json())
  labels.set("_origin_rule", "ImportNamed".to_json())
  let code = lower_to_code(
    [("IRImport", labels)],
    [],
    "src",
    "tgt",
    "@@UNRESOLVED@@",
    lift,
    lower,
  )
  inspect(code.contains("use @fs"), content="true")
}
