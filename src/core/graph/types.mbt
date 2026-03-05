// Type definitions for code graph structures.
// Based on KGF (Knowledge Graph Framework) design.

///|
/// Module node representing a source file or module in the codebase.
pub struct ModuleNode {
  /// Unique identifier for the module (e.g., package path).
  id : String
  /// Optional file path associated with this module.
  file : String?
} derive(Eq, Show, ToJson, @json.FromJson)

///|
/// Symbol node representing a named entity (function, type, variable, etc.).
pub(all) struct SymbolNode {
  /// Unique identifier for the symbol.
  id : String
  /// Human-readable name of the symbol.
  name : String
  /// Kind of symbol (e.g., "function", "type", "variable", "struct").
  kind : String
  /// Namespace the symbol belongs to (e.g., module path segment).
  ns : String
  /// Module ID this symbol is declared in.
  module_id : String
  /// Documentation comment for the symbol (optional).
  doc : String?
} derive(Eq, Show, ToJson, @json.FromJson)

///|
/// Edge kinds representing relationships between nodes.
pub enum EdgeKind {
  /// A module declares a symbol.
  Declares
  /// A symbol references another symbol.
  References
  /// A module depends on another module.
  ModuleDependsOn
  /// A symbol imports another symbol.
  Imports
  /// A symbol calls another symbol (function call).
  Calls
  /// A symbol extends/inherits from another symbol.
  Extends
  /// A symbol implements an interface/trait.
  Implements
  /// A circular dependency was detected.
  CircularDependency
  /// Custom edge kind for extensibility.
  Custom(String)
} derive(Eq, Show, ToJson, @json.FromJson)

///|
/// Edge representing a directed relationship between two nodes.
pub struct Edge {
  /// The kind of relationship.
  kind : EdgeKind
  /// Source node ID.
  from : String
  /// Target node ID.
  to : String
  /// Optional attributes for additional metadata.
  attrs : Map[String, String]
} derive(Eq, Show, ToJson, @json.FromJson)

///|
/// The main code graph structure containing modules, symbols, and edges.
pub struct CodeGraph {
  /// Map of module ID to module node.
  modules : Map[String, ModuleNode]
  /// Map of symbol ID to symbol node.
  symbols : Map[String, SymbolNode]
  /// List of edges connecting nodes.
  edges : Array[Edge]
} derive(Eq, Show, ToJson, @json.FromJson)
