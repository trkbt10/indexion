// Query result types for extracting information from CodeGraph.

///|
/// Module dependency information extracted from ModuleDependsOn edges.
pub struct ModuleDep {
  from : String
  to : String
  via : String?
  dep_kind : String?
}

///|
/// Create a new ModuleDep.
pub fn ModuleDep::new(
  from : String,
  to : String,
  via? : String? = None,
  dep_kind? : String? = None,
) -> ModuleDep {
  { from, to, via, dep_kind }
}

///|
/// Call relationship extracted from Calls edges.
pub struct CallInfo {
  caller : String
  callee : String
  file : String
}

///|
/// Create a new CallInfo.
pub fn CallInfo::new(
  caller : String,
  callee : String,
  file : String,
) -> CallInfo {
  { caller, callee, file }
}

///|
/// Type hierarchy relationship extracted from Extends/Implements edges.
pub struct TypeRelation {
  child : String
  parent : String
  relation : String
}

///|
/// Create a new TypeRelation.
pub fn TypeRelation::new(
  child : String,
  parent : String,
  relation : String,
) -> TypeRelation {
  { child, parent, relation }
}

///|
/// Symbol reference extracted from References edges.
pub struct SymbolRef {
  symbol : String
  ref_site : String
  ref_kind : String
}

///|
/// Create a new SymbolRef.
pub fn SymbolRef::new(
  symbol : String,
  ref_site : String,
  ref_kind : String,
) -> SymbolRef {
  { symbol, ref_site, ref_kind }
}

///|
/// Symbol declaration with documentation.
pub struct SymbolDecl {
  id : String
  name : String
  kind : String
  module_id : String
  doc : String?
}

///|
/// Create a new SymbolDecl.
pub fn SymbolDecl::new(
  id : String,
  name : String,
  kind : String,
  module_id : String,
  doc? : String? = None,
) -> SymbolDecl {
  { id, name, kind, module_id, doc }
}

// Getters

///|
pub fn ModuleDep::get_from(self : ModuleDep) -> String {
  self.from
}

///|
pub fn ModuleDep::get_to(self : ModuleDep) -> String {
  self.to
}

///|
pub fn ModuleDep::get_via(self : ModuleDep) -> String? {
  self.via
}

///|
pub fn ModuleDep::get_dep_kind(self : ModuleDep) -> String? {
  self.dep_kind
}

///|
pub fn CallInfo::get_caller(self : CallInfo) -> String {
  self.caller
}

///|
pub fn CallInfo::get_callee(self : CallInfo) -> String {
  self.callee
}

///|
pub fn CallInfo::get_file(self : CallInfo) -> String {
  self.file
}

///|
pub fn TypeRelation::get_child(self : TypeRelation) -> String {
  self.child
}

///|
pub fn TypeRelation::get_parent(self : TypeRelation) -> String {
  self.parent
}

///|
pub fn TypeRelation::get_relation(self : TypeRelation) -> String {
  self.relation
}

///|
pub fn SymbolRef::get_symbol(self : SymbolRef) -> String {
  self.symbol
}

///|
pub fn SymbolRef::get_ref_site(self : SymbolRef) -> String {
  self.ref_site
}

///|
pub fn SymbolRef::get_ref_kind(self : SymbolRef) -> String {
  self.ref_kind
}

///|
pub fn SymbolDecl::get_id(self : SymbolDecl) -> String {
  self.id
}

///|
pub fn SymbolDecl::get_name(self : SymbolDecl) -> String {
  self.name
}

///|
pub fn SymbolDecl::get_kind(self : SymbolDecl) -> String {
  self.kind
}

///|
pub fn SymbolDecl::get_module_id(self : SymbolDecl) -> String {
  self.module_id
}

///|
pub fn SymbolDecl::get_doc(self : SymbolDecl) -> String? {
  self.doc
}
