///|
pub enum XPathToken {
  AxisName(String)
  NodeType(String)
} derive(Eq, Show)

///|
let xpath_axis_names : Array[String] = ["ancestor", "child"]

///|
let xpath_node_types : Array[String] = ["comment", "text"]
