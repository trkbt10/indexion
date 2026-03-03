///|
/// SemExpr represents a semantic expression in the KGF DSL.
pub enum SemExpr {
  Str(String)
  Num(Double)
  Bool(Bool)
  Null
  Var(String)
  Call(String, Array[SemExpr])
  Func(String, Array[SemExpr])
}

///|
/// Creates a string expression.
pub fn SemExpr::str(value : String) -> SemExpr {
  Str(value)
}

///|
/// Creates a number expression.
pub fn SemExpr::num(value : Double) -> SemExpr {
  Num(value)
}

///|
/// Creates a boolean expression.
pub fn SemExpr::bool(value : Bool) -> SemExpr {
  Bool(value)
}

///|
/// Creates a null expression.
pub fn SemExpr::null() -> SemExpr {
  Null
}

///|
/// Creates a variable expression.
pub fn SemExpr::variable(name : String) -> SemExpr {
  Var(name)
}

///|
/// Creates a call expression.
pub fn SemExpr::call(name : String, args : Array[SemExpr]) -> SemExpr {
  Call(name, args)
}

///|
/// Creates a function expression.
pub fn SemExpr::func(name : String, args : Array[SemExpr]) -> SemExpr {
  Func(name, args)
}

///|
/// SemStmt represents a semantic statement in the KGF DSL.
pub enum SemStmt {
  Edge(edge_kind~ : String, from~ : SemExpr, to~ : SemExpr, attrs~ : SemExpr?)
  Bind(ns~ : SemExpr, name~ : SemExpr, to~ : SemExpr)
  Note(note_type~ : String, payload~ : SemExpr?)
  Let(id~ : String, value~ : SemExpr)
  For(id~ : String, iter~ : SemExpr, body~ : Array[SemStmt])
  Module(id~ : SemExpr, file~ : SemExpr?)
}

///|
/// Creates an edge statement.
pub fn SemStmt::edge(
  edge_kind : String,
  from : SemExpr,
  to : SemExpr,
  attrs? : SemExpr? = None,
) -> SemStmt {
  Edge(edge_kind~, from~, to~, attrs~)
}

///|
/// Creates a bind statement.
pub fn SemStmt::bind(ns : SemExpr, name : SemExpr, to : SemExpr) -> SemStmt {
  Bind(ns~, name~, to~)
}

///|
/// Creates a note statement.
pub fn SemStmt::note(note_type : String, payload? : SemExpr? = None) -> SemStmt {
  Note(note_type~, payload~)
}

///|
/// Creates a let statement.
pub fn SemStmt::let_(id : String, value : SemExpr) -> SemStmt {
  Let(id~, value~)
}

///|
/// Creates a for statement.
pub fn SemStmt::for_(
  id : String,
  iter : SemExpr,
  body : Array[SemStmt],
) -> SemStmt {
  For(id~, iter~, body~)
}

///|
/// Creates a module statement.
pub fn SemStmt::mod_(id : SemExpr, file? : SemExpr? = None) -> SemStmt {
  Module(id~, file~)
}

///|
/// SemOnBlock represents a semantic on-block definition.
/// Contains a rule name, optional when condition, then statements, and optional else statements.
pub struct SemOnBlock {
  rule : String
  when_cond : SemExpr?
  then_stmts : Array[SemStmt]
  else_stmts : Array[SemStmt]?
}

///|
/// Creates a new SemOnBlock with the specified parameters.
pub fn SemOnBlock::new(
  rule : String,
  then_stmts : Array[SemStmt],
  when_cond? : SemExpr? = None,
  else_stmts? : Array[SemStmt]? = None,
) -> SemOnBlock {
  { rule, when_cond, then_stmts, else_stmts }
}

///|
/// Returns the rule name.
pub fn SemOnBlock::get_rule(self : SemOnBlock) -> String {
  self.rule
}

///|
/// Returns the when condition.
pub fn SemOnBlock::get_when_cond(self : SemOnBlock) -> SemExpr? {
  self.when_cond
}

///|
/// Returns the then statements.
pub fn SemOnBlock::get_then_stmts(self : SemOnBlock) -> Array[SemStmt] {
  self.then_stmts
}

///|
/// Returns the else statements.
pub fn SemOnBlock::get_else_stmts(self : SemOnBlock) -> Array[SemStmt]? {
  self.else_stmts
}
