///|
fn idl_member(name : String, kind : String) -> (String, String) {
  (name, kind)
}

///|
fn all_implemented(
  name : String,
  members : Array[(String, String)],
) -> (String, Array[(String, String)]) {
  (name, members)
}

///|
fn surface() -> Unit {
  let _node = {
    interface: "Node",
    members: [idl_member("inventedName", "method")],
  }
  let _parent = all_implemented("ParentNode", [("append", "method")])
  let _window = { interface: "Window", members: [] }
  ()
}
