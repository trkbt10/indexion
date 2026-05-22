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
fn all_missing(
  name : String,
  members : Array[(String, String)],
) -> (String, Array[(String, String)]) {
  (name, members)
}

///|
fn surface() -> Unit {
  let _node = {
    interface: "Node",
    members: [
      idl_member("nodeType", "attribute"),
      idl_member("appendChild", "method"),
    ],
  }
  let _parent = all_implemented("ParentNode", [idl_member("append", "method")])
  let _listener = all_missing(
    "EventListener",
    [idl_member("handleEvent", "method")],
  )
  let _window = all_missing("Window", [("event", "attribute")])
  ()
}
