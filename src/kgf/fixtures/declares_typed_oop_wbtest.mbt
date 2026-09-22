///|
/// Regression tests for the typed/OOP language specs (Go, Kotlin, Java, C#,
/// Dart, Swift).
///
/// Every test here pins ONE root cause that previously made `indexion check`
/// report a partial parse — the start rule matched a prefix and everything
/// after it was silently dropped from the graph — or made a declaration a
/// reader would expect disappear even though the file parsed.
///
/// The helpers mirror the ones in `declares_wbtest.mbt` and carry a
/// `typed_oop_` prefix so the two files can coexist in this package.

///|
/// Helper: run the full KGF pipeline (lex, parse, semantics) on inline source
/// and return the resulting graph, or None when parsing fails outright.
fn typed_oop_graph(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> @graph.CodeGraph? {
  let spec = registry.get_spec(lang).unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
  let peg = @peg.build_peg(spec) catch { _ => return None }
  let start_rule = spec.get_start_rule()
  let parse_result = match @peg.run_parse(peg, spec, start_rule, tokens) {
    Some(r) => r
    None => return None
  }
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(path, file=Some(path))
  let ctx = @semantics.SemEvalCtx::new(spec, graph, path, "", lang, fn(_) {
    false
  })
  for event in parse_result.get_events() {
    @semantics.eval_rule_semantics(event.0, event.1, ctx)
  }
  Some(graph)
}

///|
/// Helper: true when the whole token stream was consumed by the start rule.
/// A partial parse is the failure mode these tests exist to catch: the file
/// still "parses", but every declaration after the stopping point is lost.
fn typed_oop_parses_fully(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
) -> Bool {
  let spec = registry.get_spec(lang).unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
  let peg = @peg.build_peg(spec) catch { _ => return false }
  let start_rule = spec.get_start_rule()
  let (_, diag) = @peg.run_parse_with_diagnostics(peg, spec, start_rule, tokens)
  diag.is_fully_consumed()
}

///|
/// Helper: the declares edges of inline source as (from, name, kind, doc)
/// tuples, in emission order.
fn typed_oop_declares(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> Array[(String, String, String, String)] {
  let result : Array[(String, String, String, String)] = []
  let graph = match typed_oop_graph(registry, lang, source, path) {
    Some(g) => g
    None => return result
  }
  for edge in graph.get_edges() {
    if !(edge.kind is @graph.Declares) {
      continue
    }
    result.push(
      (
        edge.from,
        edge.attrs.get("name").unwrap_or(""),
        edge.attrs.get("kind").unwrap_or(""),
        edge.attrs.get("doc").unwrap_or(""),
      ),
    )
  }
  result
}

///|
/// Helper: the (name, kind) pairs of the declares edges, as a map. Duplicate
/// names would be invisible here, so tests that care about duplication assert
/// on the array length as well.
fn typed_oop_kinds(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> Map[String, String] {
  let names : Map[String, String] = Map([])
  for row in typed_oop_declares(registry, lang, source, path) {
    names.set(row.1, row.2)
  }
  names
}

///|
/// Helper: the `from` endpoint of the declares edge that declares `name`, or
/// "" when nothing declares it. This is how a test checks that a member hangs
/// off its own type rather than off the file.
fn typed_oop_owner_of(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> String {
  for row in typed_oop_declares(registry, lang, source, path) {
    if row.1 == name {
      return row.0
    }
  }
  ""
}

///|
/// Helper: the doc attached to the declares edge for `name`, or "".
fn typed_oop_doc_of(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> String {
  for row in typed_oop_declares(registry, lang, source, path) {
    if row.1 == name {
      return row.3
    }
  }
  ""
}

///|
/// Helper: how many declares edges carry `name`. Used to pin down the
/// duplicate-emission bug, where a body was parsed twice — once inside its
/// type and once again at top level.
fn typed_oop_count_of(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> Int {
  let mut n = 0
  for row in typed_oop_declares(registry, lang, source, path) {
    if row.1 == name {
      n += 1
    }
  }
  n
}

///|
/// Helper: the `via` attrs of the moduleDependsOn edges. Also pins the
/// duplicate-import bug: an `=== attrs` `import` directive emits its own
/// moduleDependsOn edge, so a spec that had both it and an `=== semantics`
/// rule produced two identical edges per import.
fn typed_oop_import_vias(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> Array[String] {
  let result : Array[String] = []
  let graph = match typed_oop_graph(registry, lang, source, path) {
    Some(g) => g
    None => return result
  }
  for edge in graph.get_edges() {
    if edge.kind is @graph.ModuleDependsOn {
      result.push(edge.attrs.get("via").unwrap_or(""))
    }
  }
  result
}

///|
/// Helper: the moduleDependsOn edges as (via, target) pairs, with a caller-
/// supplied set of existing file paths. `$findAncestor` and `$resolveFrom`
/// both consult this set, so a test can stand up a whole project layout
/// in-memory and check that an import resolves to the right source file.
fn typed_oop_imports_with_files(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  existing : Array[String],
) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  let spec = registry.get_spec(lang).unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
  let peg = @peg.build_peg(spec) catch { _ => return result }
  let start_rule = spec.get_start_rule()
  let parse_result = match @peg.run_parse(peg, spec, start_rule, tokens) {
    Some(r) => r
    None => return result
  }
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(path, file=Some(path))
  let ctx = @semantics.SemEvalCtx::new(spec, graph, path, "", lang, fn(
    probe : String,
  ) {
    existing.iter().any(fn(p) { p == probe })
  })
  for event in parse_result.get_events() {
    @semantics.eval_rule_semantics(event.0, event.1, ctx)
  }
  for edge in graph.get_edges() {
    if edge.kind is @graph.ModuleDependsOn {
      result.push((edge.attrs.get("via").unwrap_or(""), edge.to))
    }
  }
  result
}

// ─── Go ─────────────────────────────────────────────────────

///|
/// Root cause: the top-level `Other` catch-all only accepted balanced atoms,
/// so a package-level composite literal (`var rootCmd = &cobra.Command{ … }`)
/// stopped the module parse at its `{` and every declaration below it — here
/// `Execute` — vanished from the graph.
test "declares(typed_oop): go composite literal in a package-level var" {
  let registry = get_fixture_registry()
  let source =
    #|package cmd
    #|
    #|var rootCmd = &cobra.Command{
    #|	Use: "svc",
    #|	Run: func(cmd *cobra.Command, args []string) {
    #|		log.Print("hi")
    #|	},
    #|}
    #|
    #|func Execute() {}
  assert_true(typed_oop_parses_fully(registry, "go", source))
  let names = typed_oop_kinds(registry, "go", source, "root.go")
  assert_true(names.get("rootCmd") == None)
  assert_true(names.get("Execute") == Some("Function"))
}

///|
/// Root cause: `KeywordType` gave Go's predeclared type names (`int`,
/// `string`, `error`, `any`, …) their own token, ahead of `Ident`. None of
/// them is a reserved word, so a struct field or parameter spelled like one
/// made the whole declaration unmatchable and took the rest of the file with
/// it.
test "declares(typed_oop): go predeclared names used as identifiers" {
  let registry = get_fixture_registry()
  let source =
    #|package p
    #|
    #|type Result struct {
    #|	Error  string
    #|	Any    int
    #|}
    #|
    #|func New() error { return nil }
  assert_true(typed_oop_parses_fully(registry, "go", source))
  let names = typed_oop_kinds(registry, "go", source, "p.go")
  assert_true(names.get("Result") == Some("Type"))
  assert_true(names.get("New") == Some("Function"))
}

///|
/// A method belongs to its receiver type. It used to be declared at file level
/// as a plain Function, indistinguishable from a free function of the same
/// name. Struct fields and interface methods were not declared at all.
test "declares(typed_oop): go method attaches to its receiver type" {
  let registry = get_fixture_registry()
  let source =
    #|package p
    #|
    #|// Server serves.
    #|type Server struct {
    #|	// Addr is the listen address.
    #|	Addr string
    #|	hidden int
    #|}
    #|
    #|// Run starts the server.
    #|func (s *Server) Run(addr string) error { return nil }
    #|
    #|// New builds one.
    #|func New() *Server { return nil }
  assert_true(typed_oop_parses_fully(registry, "go", source))
  let names = typed_oop_kinds(registry, "go", source, "p.go")
  assert_true(names.get("Server") == Some("Type"))
  assert_true(names.get("Run") == Some("Method"))
  assert_true(names.get("New") == Some("Function"))
  assert_true(names.get("Addr") == Some("Field"))
  // unexported field stays out of the graph
  assert_true(names.get("hidden") == None)
  // the method and the field hang off the type, the free function off the file
  assert_eq(
    typed_oop_owner_of(registry, "go", source, "p.go", "Run"),
    "p.go::Server",
  )
  assert_eq(
    typed_oop_owner_of(registry, "go", source, "p.go", "Addr"),
    "p.go::Server",
  )
  assert_eq(typed_oop_owner_of(registry, "go", source, "p.go", "New"), "p.go")
}

///|
/// Root cause: the doc capture lived on a shared prefix rule, and a label
/// binds only inside the rule that writes it — so `$doc` was invisible to the
/// declaration's own semantics and every Go doc comment came out empty. The
/// grouped forms additionally lost their docs because the `DocComment`
/// alternative was tried before the spec rule and consumed them first.
test "declares(typed_oop): go doc comments reach single and grouped decls" {
  let registry = get_fixture_registry()
  let source =
    #|package p
    #|
    #|// Kind is an enum.
    #|type Kind int
    #|
    #|const (
    #|	// KindA is the first.
    #|	KindA Kind = iota
    #|)
    #|
    #|var (
    #|	// ErrNope is returned when nope.
    #|	ErrNope = fmt.Errorf("nope")
    #|)
  assert_true(typed_oop_parses_fully(registry, "go", source))
  assert_eq(
    typed_oop_doc_of(registry, "go", source, "p.go", "Kind"),
    "Kind is an enum.",
  )
  assert_eq(
    typed_oop_doc_of(registry, "go", source, "p.go", "KindA"),
    "KindA is the first.",
  )
  assert_eq(
    typed_oop_doc_of(registry, "go", source, "p.go", "ErrNope"),
    "ErrNope is returned when nope.",
  )
}

// ─── Kotlin ─────────────────────────────────────────────────

///|
/// Root cause: `?` was part of the generic `Operator` character class, which
/// the lexer tries before the dedicated `QMARK` token (first match wins, not
/// longest match). `Type -> TypeAtom QMARK?` could therefore never match a
/// nullable type, so `suspend fun getById(id: Long): Task?` failed and took
/// the whole interface — and the rest of the file — down with it.
test "declares(typed_oop): kotlin nullable return type" {
  let registry = get_fixture_registry()
  let source =
    #|interface TaskRepository {
    #|    suspend fun getById(id: Long): Task?
    #|    fun findAll(): Flow<Task>
    #|}
    #|
    #|class After
  assert_true(typed_oop_parses_fully(registry, "kotlin", source))
  let names = typed_oop_kinds(registry, "kotlin", source, "R.kt")
  assert_true(names.get("TaskRepository") == Some("Interface"))
  assert_true(names.get("getById") == Some("Method"))
  assert_true(names.get("findAll") == Some("Method"))
  assert_true(names.get("After") == Some("Class"))
}

///|
/// Root cause: Kotlin's soft keywords (`data`, `get`, `open`, `set`, `by`, …)
/// had lexer tokens, which shadow `Ident` everywhere. Each of these is a legal
/// identifier, so a property named `data` or a function named `get` made its
/// declaration unmatchable.
test "declares(typed_oop): kotlin soft keywords as ordinary names" {
  let registry = get_fixture_registry()
  let source =
    #|class Holder {
    #|    val data: String = ""
    #|    fun get(open: Int, sealed: String): Int = open
    #|}
  assert_true(typed_oop_parses_fully(registry, "kotlin", source))
  let names = typed_oop_kinds(registry, "kotlin", source, "H.kt")
  assert_true(names.get("data") == Some("Property"))
  assert_true(names.get("get") == Some("Method"))
}

///|
/// Root cause: the class-member catch-all accepted `}`, so the member list ran
/// past the body's closing brace to end of file. `ClassBody`'s own `RBRACE`
/// then never matched, and `Item*` re-parsed the whole body at top level:
/// every member was declared twice and detached from its class.
test "declares(typed_oop): kotlin members are declared once, under the class" {
  let registry = get_fixture_registry()
  let source =
    #|class C {
    #|    fun a(): Int = 1
    #|}
  assert_true(typed_oop_parses_fully(registry, "kotlin", source))
  let rows = typed_oop_declares(registry, "kotlin", source, "C.kt")
  assert_eq(rows.length(), 2)
  assert_eq(typed_oop_count_of(registry, "kotlin", source, "C.kt", "a"), 1)
  assert_eq(
    typed_oop_owner_of(registry, "kotlin", source, "C.kt", "a"),
    "C.kt::C",
  )
}

///|
/// Root cause: a parameter default value was a general expression, and a
/// general expression accepts `,` as an atom — so the first parameter's
/// default swallowed every parameter after it. A `data class`'s constructor
/// properties past the first one silently disappeared, and the class body was
/// never reached.
test "declares(typed_oop): kotlin constructor properties with defaults" {
  let registry = get_fixture_registry()
  let source =
    #|data class Task(
    #|    val id: Long = 0,
    #|    val title: String,
    #|    val status: Status = Status.PENDING,
    #|) {
    #|    /** Marks it done. */
    #|    fun complete(): Task = copy()
    #|}
  assert_true(typed_oop_parses_fully(registry, "kotlin", source))
  let names = typed_oop_kinds(registry, "kotlin", source, "T.kt")
  assert_true(names.get("id") == Some("Property"))
  assert_true(names.get("title") == Some("Property"))
  assert_true(names.get("status") == Some("Property"))
  assert_true(names.get("complete") == Some("Method"))
  assert_eq(
    typed_oop_owner_of(registry, "kotlin", source, "T.kt", "title"),
    "T.kt::Task",
  )
  assert_eq(
    typed_oop_doc_of(registry, "kotlin", source, "T.kt", "complete"),
    "Marks it done.",
  )
}

///|
/// `bind`/`$scope` is a flat map, so the enclosing type has to be kept as an
/// explicit stack: a nested type must be declared under its parent, and a
/// top-level declaration written AFTER a class body must go back to file
/// level rather than being attributed to that class.
test "declares(typed_oop): kotlin nesting restores the enclosing type" {
  let registry = get_fixture_registry()
  let source =
    #|class Outer {
    #|    object Nested
    #|    fun inside() {}
    #|}
    #|
    #|fun top() {}
  assert_true(typed_oop_parses_fully(registry, "kotlin", source))
  assert_eq(
    typed_oop_owner_of(registry, "kotlin", source, "O.kt", "Nested"),
    "O.kt::Outer",
  )
  assert_eq(
    typed_oop_owner_of(registry, "kotlin", source, "O.kt", "inside"),
    "O.kt::Outer",
  )
  assert_eq(
    typed_oop_owner_of(registry, "kotlin", source, "O.kt", "top"),
    "O.kt",
  )
  let names = typed_oop_kinds(registry, "kotlin", source, "O.kt")
  assert_true(names.get("top") == Some("Function"))
}

///|
/// Kotlin's default visibility is public; only an explicit `private` or
/// `protected` hides a declaration. Visibility words are soft keywords, so
/// they are read out of the modifier text rather than from a keyword token.
test "declares(typed_oop): kotlin private members stay out of the graph" {
  let registry = get_fixture_registry()
  let source =
    #|private val logger = L.logger {}
    #|
    #|class S {
    #|    private val mapper = m()
    #|    fun greet(name: String): String = name
    #|}
  assert_true(typed_oop_parses_fully(registry, "kotlin", source))
  let names = typed_oop_kinds(registry, "kotlin", source, "S.kt")
  assert_true(names.get("logger") == None)
  assert_true(names.get("mapper") == None)
  assert_true(names.get("greet") == Some("Method"))
}

///|
/// An import path is a multi-token dotted name; `$path` holds only its LAST
/// token, so the dependency used to resolve to the trailing segment alone
/// (`Flow` instead of `kotlinx.coroutines.flow.Flow`).
test "declares(typed_oop): kotlin import resolves the whole dotted path" {
  let registry = get_fixture_registry()
  let source =
    #|import kotlinx.coroutines.flow.Flow
    #|
    #|class C
  let vias = typed_oop_import_vias(registry, "kotlin", source, "C.kt")
  assert_eq(vias.length(), 1)
  assert_eq(vias[0], "kotlinx.coroutines.flow.Flow")
}

///|
/// One import must yield exactly one dependency edge.
test "declares(typed_oop): one import yields one edge per language" {
  let registry = get_fixture_registry()
  assert_eq(
    typed_oop_import_vias(
      registry, "go", "package p\n\nimport (\n\t\"fmt\"\n)\n", "p.go",
    ).length(),
    1,
  )
  assert_eq(
    typed_oop_import_vias(
      registry, "java", "import java.util.List;\n", "A.java",
    ).length(),
    1,
  )
  assert_eq(
    typed_oop_import_vias(registry, "csharp", "using System.Linq;\n", "A.cs").length(),
    1,
  )
  assert_eq(
    typed_oop_import_vias(registry, "swift", "import Foundation\n", "A.swift").length(),
    1,
  )
}

// ─── Java ───────────────────────────────────────────────────

///|
/// Root cause: the declaration rule allowed `Annotation*` but no newline after
/// it, and real Java writes the annotation on its own line. `@RestController`
/// followed by `public class UserController {` therefore fell through to the
/// catch-all, which could not accept the `{`, and the module parse stopped
/// there — losing the class and every member in it.
test "declares(typed_oop): java annotation on its own line" {
  let registry = get_fixture_registry()
  let source =
    #|@RestController
    #|public class UserController {
    #|
    #|    @Autowired
    #|    private UserRepository repo;
    #|
    #|    @GetMapping("/users/{id}")
    #|    public Optional<User> get(@PathVariable long id) {
    #|        return repo.findById(id);
    #|    }
    #|}
  assert_true(typed_oop_parses_fully(registry, "java", source))
  let names = typed_oop_kinds(registry, "java", source, "C.java")
  assert_true(names.get("UserController") == Some("Class"))
  assert_true(names.get("get") == Some("Method"))
  // a private field is not part of the public surface
  assert_true(names.get("repo") == None)
  assert_eq(
    typed_oop_owner_of(registry, "java", source, "C.java", "get"),
    "C.java::UserController",
  )
}

///|
/// Root cause: `var` had a `KeywordType` token. It is a reserved TYPE NAME in
/// Java, not a reserved word, so it stays a legal name for a field, parameter
/// or method — `int var = 1;` compiles — and the token shadowed `Ident`
/// everywhere, making such declarations unmatchable.
test "declares(typed_oop): java var used as an ordinary name" {
  let registry = get_fixture_registry()
  let source =
    #|public class C {
    #|    public int var = 1;
    #|    public void after() {}
    #|}
  assert_true(typed_oop_parses_fully(registry, "java", source))
  let names = typed_oop_kinds(registry, "java", source, "C.java")
  assert_true(names.get("var") == Some("Field"))
  assert_true(names.get("after") == Some("Method"))
}

///|
/// An interface member is implicitly public with no modifier written at all,
/// while a class member with no modifier is package-private. The grammar could
/// not tell the two bodies apart, so interface requirements were dropped.
test "declares(typed_oop): java interface members are implicitly public" {
  let registry = get_fixture_registry()
  let source =
    #|public interface Shape {
    #|    /** Its area. */
    #|    double area();
    #|}
    #|
    #|public class Impl {
    #|    void packagePrivate() {}
    #|    public void published() {}
    #|}
  assert_true(typed_oop_parses_fully(registry, "java", source))
  let names = typed_oop_kinds(registry, "java", source, "S.java")
  assert_true(names.get("area") == Some("Method"))
  assert_eq(
    typed_oop_doc_of(registry, "java", source, "S.java", "area"),
    "Its area.",
  )
  assert_true(names.get("packagePrivate") == None)
  assert_true(names.get("published") == Some("Method"))
}

///|
/// Nested types belong to their enclosing type, and a member written after a
/// nested type's body belongs to the outer type again.
test "declares(typed_oop): java nesting restores the enclosing type" {
  let registry = get_fixture_registry()
  let source =
    #|public class Outer {
    #|    public static class Inner {
    #|        public void go() {}
    #|    }
    #|    public void after() {}
    #|}
  assert_true(typed_oop_parses_fully(registry, "java", source))
  assert_eq(
    typed_oop_owner_of(registry, "java", source, "O.java", "Inner"),
    "O.java::Outer",
  )
  assert_eq(
    typed_oop_owner_of(registry, "java", source, "O.java", "go"),
    "O.java::Outer.Inner",
  )
  assert_eq(
    typed_oop_owner_of(registry, "java", source, "O.java", "after"),
    "O.java::Outer",
  )
}

///|
/// A record's components are its public accessors; they were not declared at
/// all before, because the component list was parsed inside the header and so
/// fired its events BEFORE the header published the record.
test "declares(typed_oop): java record components and enum constants" {
  let registry = get_fixture_registry()
  let source =
    #|public record Circle(double radius, String label) {}
    #|
    #|public enum Status {
    #|    /** Not started. */
    #|    PENDING,
    #|    ACTIVE;
    #|}
  assert_true(typed_oop_parses_fully(registry, "java", source))
  let names = typed_oop_kinds(registry, "java", source, "M.java")
  assert_true(names.get("Circle") == Some("Record"))
  assert_true(names.get("radius") == Some("RecordComponent"))
  assert_true(names.get("label") == Some("RecordComponent"))
  assert_eq(
    typed_oop_owner_of(registry, "java", source, "M.java", "radius"),
    "M.java::Circle",
  )
  assert_true(names.get("PENDING") == Some("EnumConstant"))
  assert_true(names.get("ACTIVE") == Some("EnumConstant"))
  assert_eq(
    typed_oop_doc_of(registry, "java", source, "M.java", "PENDING"),
    "Not started.",
  )
}

// ─── C# ─────────────────────────────────────────────────────

///|
/// Root cause: a positional record's parameters were matched with `Ident`
/// only, but the lexer splits identifiers by first-letter case and C# names
/// properties in PascalCase — so `public record User(int Id, string Name);`
/// stopped the parse at its `(`.
test "declares(typed_oop): csharp positional record with PascalCase members" {
  let registry = get_fixture_registry()
  let source =
    #|/// <summary>Represents a user.</summary>
    #|public record User(int Id, string Name, string Email);
    #|
    #|public class After {}
  assert_true(typed_oop_parses_fully(registry, "csharp", source))
  let names = typed_oop_kinds(registry, "csharp", source, "U.cs")
  assert_true(names.get("User") == Some("Record"))
  assert_true(names.get("Id") == Some("Property"))
  assert_true(names.get("Name") == Some("Property"))
  assert_true(names.get("Email") == Some("Property"))
  assert_true(names.get("After") == Some("Class"))
  assert_eq(
    typed_oop_owner_of(registry, "csharp", source, "U.cs", "Id"),
    "U.cs::User",
  )
}

///|
/// Root cause: `var`, `dynamic`, `get`, `set`, `value`, `partial`, `async`
/// and `where` all had lexer tokens. Every one of them is a CONTEXTUAL keyword
/// in C# and a legal identifier elsewhere, so the tokens shadowed `Ident` and
/// broke ordinary declarations spelled with those names.
test "declares(typed_oop): csharp contextual keywords as ordinary names" {
  let registry = get_fixture_registry()
  let source =
    #|public class C
    #|{
    #|    public int var { get; set; }
    #|    public string value = "";
    #|    public void After() {}
    #|}
  assert_true(typed_oop_parses_fully(registry, "csharp", source))
  let names = typed_oop_kinds(registry, "csharp", source, "C.cs")
  assert_true(names.get("var") == Some("Property"))
  assert_true(names.get("value") == Some("Field"))
  assert_true(names.get("After") == Some("Method"))
}

///|
/// C#'s default member visibility is private and its default type visibility
/// is internal; only `public` and `protected` belong to the package surface.
/// An interface member, however, is implicitly public with no modifier.
test "declares(typed_oop): csharp visibility and implicit interface members" {
  let registry = get_fixture_registry()
  let source =
    #|public interface IThing
    #|{
    #|    /// <summary>Do it.</summary>
    #|    int Do(string s);
    #|    string Name { get; }
    #|}
    #|
    #|internal class Hidden
    #|{
    #|    private void Nope() { }
    #|}
  assert_true(typed_oop_parses_fully(registry, "csharp", source))
  let names = typed_oop_kinds(registry, "csharp", source, "I.cs")
  assert_true(names.get("IThing") == Some("Interface"))
  assert_true(names.get("Do") == Some("Method"))
  assert_true(names.get("Name") == Some("Property"))
  assert_eq(
    typed_oop_doc_of(registry, "csharp", source, "I.cs", "Do"),
    "<summary>Do it.</summary>",
  )
  assert_true(names.get("Hidden") == None)
  assert_true(names.get("Nope") == None)
}

///|
/// Root cause: an enum member's explicit value was a general expression, and a
/// general expression accepts `,` — so `Green = 2` swallowed every member
/// after it.
test "declares(typed_oop): csharp enum members past an explicit value" {
  let registry = get_fixture_registry()
  let source =
    #|public enum Color { Red, Green = 2, Blue }
  assert_true(typed_oop_parses_fully(registry, "csharp", source))
  let names = typed_oop_kinds(registry, "csharp", source, "C.cs")
  assert_true(names.get("Red") == Some("EnumMember"))
  assert_true(names.get("Green") == Some("EnumMember"))
  assert_true(names.get("Blue") == Some("EnumMember"))
}

///|
/// A method parameter must NOT become a property of the enclosing type; only a
/// positional record's parameters do. Both used to share one rule.
test "declares(typed_oop): csharp method parameters are not properties" {
  let registry = get_fixture_registry()
  let source =
    #|public class S
    #|{
    #|    public void Add(User user, int id) { }
    #|}
  assert_true(typed_oop_parses_fully(registry, "csharp", source))
  let names = typed_oop_kinds(registry, "csharp", source, "S.cs")
  assert_true(names.get("Add") == Some("Method"))
  assert_true(names.get("user") == None)
  assert_true(names.get("id") == None)
}

// ─── Dart ───────────────────────────────────────────────────

///|
/// Root cause: the top-level catch-all could not accept a brace, so the `{` of
/// a class body that the header rule had failed on stopped the module parse.
/// Here the doc comment plus the class header is exactly the fixture shape
/// that failed.
test "declares(typed_oop): dart class with a doc comment parses fully" {
  let registry = get_fixture_registry()
  let source =
    #|/// Service for managing tasks.
    #|class TaskService {
    #|  final List<Task> _tasks = [];
    #|
    #|  /// Creates a new task.
    #|  Task create(String title, {String description = ''}) {
    #|    return Task(id: 1, title: title);
    #|  }
    #|}
  assert_true(typed_oop_parses_fully(registry, "dart", source))
  let names = typed_oop_kinds(registry, "dart", source, "s.dart")
  assert_true(names.get("TaskService") == Some("Class"))
  assert_true(names.get("create") == Some("Method"))
  assert_eq(
    typed_oop_doc_of(registry, "dart", source, "s.dart", "TaskService"),
    "Service for managing tasks.",
  )
  // a leading underscore means library-private in Dart
  assert_true(names.get("_tasks") == None)
}

///|
/// Root cause: the spec's member semantics read `current_class` / `current_enum`
/// that NOTHING ever bound, so Dart declared no method, field, getter or enum
/// value at all — only top-level types.
test "declares(typed_oop): dart members attach to their class" {
  let registry = get_fixture_registry()
  let source =
    #|class Task {
    #|  final int id;
    #|  /// A summary.
    #|  String get summary => '$id';
    #|  /// Copy it.
    #|  Task copyWith({int? id}) => this;
    #|}
  assert_true(typed_oop_parses_fully(registry, "dart", source))
  let names = typed_oop_kinds(registry, "dart", source, "t.dart")
  assert_true(names.get("id") == Some("Field"))
  assert_true(names.get("summary") == Some("Getter"))
  assert_true(names.get("copyWith") == Some("Method"))
  assert_eq(
    typed_oop_owner_of(registry, "dart", source, "t.dart", "summary"),
    "t.dart::Task",
  )
  assert_eq(
    typed_oop_doc_of(registry, "dart", source, "t.dart", "copyWith"),
    "Copy it.",
  )
}

///|
/// Root cause: `get`, `set`, `on`, `base`, `interface`, `sealed`, `static`,
/// `late`, `external`, `factory`, `dynamic` and `Function` all had lexer
/// tokens. Every one is a BUILT-IN identifier in Dart — legal as a name — so
/// the tokens shadowed `Ident` and broke ordinary declarations.
test "declares(typed_oop): dart built-in identifiers as ordinary names" {
  let registry = get_fixture_registry()
  let source =
    #|class C {
    #|  int get = 1;
    #|  void set(int on) {}
    #|  String base = '';
    #|}
  assert_true(typed_oop_parses_fully(registry, "dart", source))
  let names = typed_oop_kinds(registry, "dart", source, "c.dart")
  assert_true(names.get("get") == Some("Field"))
  assert_true(names.get("set") == Some("Method"))
  assert_true(names.get("base") == Some("Field"))
}

///|
/// Root cause: a lowercase type name in a parameter (`bool complete(int id)`)
/// was eaten by the contextual-modifier rule, leaving the name to serve as
/// both type and name; the parameter list — and with it the whole method —
/// failed to parse. Separately, an `=>` body that wrapped onto the next line
/// failed because the expression rule rejected a newline.
test "declares(typed_oop): dart lowercase param types and wrapped arrow bodies" {
  let registry = get_fixture_registry()
  let source =
    #|class S {
    #|  bool complete(int id) {
    #|    return true;
    #|  }
    #|
    #|  List<Task> get pending =>
    #|      _tasks.where((t) => !t.done).toList();
    #|}
  assert_true(typed_oop_parses_fully(registry, "dart", source))
  let names = typed_oop_kinds(registry, "dart", source, "s.dart")
  assert_true(names.get("complete") == Some("Method"))
  assert_true(names.get("pending") == Some("Getter"))
}

///|
/// Root cause: the import directive modelled `deferred? (as n)? (show ns)*`,
/// and the `deferred` slot ate the `show` of `import '…' show A, B;`. The
/// leftover `A` was then parsed as a mixin declaration whose body swallowed
/// the rest of the file.
test "declares(typed_oop): dart import with a show combinator" {
  let registry = get_fixture_registry()
  let source =
    #|import 'dart:async' show Future, Stream;
    #|
    #|/// After.
    #|class After {}
  assert_true(typed_oop_parses_fully(registry, "dart", source))
  let names = typed_oop_kinds(registry, "dart", source, "a.dart")
  assert_true(names.get("After") == Some("Class"))
  assert_true(names.get("Future") == None)
  let vias = typed_oop_import_vias(registry, "dart", source, "a.dart")
  assert_eq(vias.length(), 1)
  assert_eq(vias[0], "dart:async")
}

///|
/// `mixin M on B {}`, `extension E on B {}` and `typedef T = …;` all have the
/// same token shape, so each needs its own keyword to be told apart.
test "declares(typed_oop): dart mixin, extension and typedef are distinct" {
  let registry = get_fixture_registry()
  let source =
    #|mixin Loggable on Repo {
    #|  void log(String m) {}
    #|}
    #|
    #|extension Pretty on String {
    #|  String get pretty => trim();
    #|}
    #|
    #|typedef Cb = void Function(int);
  assert_true(typed_oop_parses_fully(registry, "dart", source))
  let names = typed_oop_kinds(registry, "dart", source, "m.dart")
  assert_true(names.get("Loggable") == Some("Mixin"))
  assert_true(names.get("Pretty") == Some("Extension"))
  assert_true(names.get("Cb") == Some("Typedef"))
  assert_true(names.get("log") == Some("Method"))
  assert_true(names.get("pretty") == Some("Getter"))
}

// ─── Swift ──────────────────────────────────────────────────

///|
/// Root cause: `VarDecl` never bound a `vis` label while its semantics tested
/// `when $vis`, so EVERY Swift `let` / `var` declaration in every file was
/// silently dropped — including the public stored properties of a public
/// struct.
test "declares(typed_oop): swift let and var declarations are not dropped" {
  let registry = get_fixture_registry()
  let source =
    #|public struct User {
    #|    public let name: String
    #|    public var age: Int
    #|    private let secret: String
    #|}
  assert_true(typed_oop_parses_fully(registry, "swift", source))
  let names = typed_oop_kinds(registry, "swift", source, "U.swift")
  assert_true(names.get("name") == Some("Property"))
  assert_true(names.get("age") == Some("Property"))
  assert_true(names.get("secret") == None)
  assert_eq(
    typed_oop_owner_of(registry, "swift", source, "U.swift", "name"),
    "U.swift::User",
  )
}

///|
/// Root cause: the inheritance clause was spelled out as exactly one, two or
/// three conforming types, so a fourth conformance failed the declaration —
/// and, since the header failed, its `{` stopped the module parse.
test "declares(typed_oop): swift inheritance clause of any length" {
  let registry = get_fixture_registry()
  let source =
    #|public struct S: A, B, C, D, E {
    #|    public func f() {}
    #|}
  assert_true(typed_oop_parses_fully(registry, "swift", source))
  let names = typed_oop_kinds(registry, "swift", source, "S.swift")
  assert_true(names.get("S") == Some("Struct"))
  assert_true(names.get("f") == Some("Method"))
}

///|
/// Root cause: the lexer had no token for `$0` / `$binding`, so it reported
/// "unrecognized input" at the bare `$` — two such errors in the Swift
/// fixtures alone.
test "declares(typed_oop): swift closure shorthand arguments lex cleanly" {
  let registry = get_fixture_registry()
  let source =
    #|public class Store {
    #|    @Published private(set) var tasks: [Task] = []
    #|
    #|    /// All pending.
    #|    public var pending: [Task] {
    #|        tasks.filter { !$0.done }
    #|    }
    #|}
  assert_true(typed_oop_parses_fully(registry, "swift", source))
  let names = typed_oop_kinds(registry, "swift", source, "S.swift")
  assert_true(names.get("Store") == Some("Class"))
  assert_true(names.get("pending") == Some("Property"))
  assert_true(names.get("tasks") == None)
  assert_eq(
    typed_oop_doc_of(registry, "swift", source, "S.swift", "pending"),
    "All pending.",
  )
}

///|
/// Root cause: `get`, `set`, `open`, `final`, `static`, `override`,
/// `mutating`, `async`, `await` and `actor` had lexer tokens. All are
/// CONTEXTUAL keywords in Swift and legal identifiers, so the tokens shadowed
/// `Ident`. (`KW_get` / `KW_set` were in fact already dead: they were defined
/// after `Ident`, which matches first, so the accessor rule that referenced
/// them could never fire.)
test "declares(typed_oop): swift contextual keywords as ordinary names" {
  let registry = get_fixture_registry()
  let source =
    #|public struct S {
    #|    public let get: Int = 1
    #|    public var open: String = ""
    #|    public func set(actor: Int) {}
    #|}
  assert_true(typed_oop_parses_fully(registry, "swift", source))
  let names = typed_oop_kinds(registry, "swift", source, "S.swift")
  assert_true(names.get("get") == Some("Property"))
  assert_true(names.get("open") == Some("Property"))
  assert_true(names.get("set") == Some("Method"))
}

///|
/// Root cause: a stray `Operator?` sat between a parameter's type and its
/// default value. `=` is lexed as `Operator`, so that slot ate the `=` and the
/// default never matched — dropping every initializer and function that had a
/// default argument. A second `Operator` alternative in the type's own suffix
/// list did the same thing.
test "declares(typed_oop): swift default argument values" {
  let registry = get_fixture_registry()
  let source =
    #|public struct Greeter {
    #|    private let logger: Logger
    #|
    #|    public init(logger: Logger = Logger(label: "x")) {
    #|        self.logger = logger
    #|    }
    #|
    #|    /// Greets.
    #|    public func greet(_ user: User) -> String { return "hi" }
    #|}
  assert_true(typed_oop_parses_fully(registry, "swift", source))
  let names = typed_oop_kinds(registry, "swift", source, "G.swift")
  assert_true(names.get("Greeter") == Some("Struct"))
  assert_true(names.get("init") == Some("Initializer"))
  assert_true(names.get("greet") == Some("Method"))
  assert_true(names.get("logger") == None)
  assert_eq(
    typed_oop_doc_of(registry, "swift", source, "G.swift", "greet"),
    "Greets.",
  )
}

///|
/// A protocol requirement is implicitly public with no modifier written at
/// all, so it must be published whenever the protocol is. An enum case and an
/// associated type are members of their type for the same reason.
test "declares(typed_oop): swift protocol requirements, cases, assoc types" {
  let registry = get_fixture_registry()
  let source =
    #|public protocol Validator {
    #|    associatedtype Input
    #|    /// Validates.
    #|    func validate(_ input: Any) -> Bool
    #|    var name: String { get }
    #|}
    #|
    #|public enum Status {
    #|    /// Waiting.
    #|    case pending
    #|    case active, done
    #|}
  assert_true(typed_oop_parses_fully(registry, "swift", source))
  let names = typed_oop_kinds(registry, "swift", source, "V.swift")
  assert_true(names.get("Validator") == Some("Protocol"))
  assert_true(names.get("validate") == Some("Method"))
  assert_true(names.get("name") == Some("Property"))
  assert_true(names.get("Input") == Some("AssociatedType"))
  assert_eq(
    typed_oop_doc_of(registry, "swift", source, "V.swift", "validate"),
    "Validates.",
  )
  assert_true(names.get("pending") == Some("EnumCase"))
  assert_true(names.get("active") == Some("EnumCase"))
  assert_true(names.get("done") == Some("EnumCase"))
  assert_eq(
    typed_oop_owner_of(registry, "swift", source, "V.swift", "pending"),
    "V.swift::Status",
  )
}

///|
/// An extension has no name of its own; its members belong to the type it
/// extends, and a declaration after the extension body returns to file level.
test "declares(typed_oop): swift extension members attach to the extended type" {
  let registry = get_fixture_registry()
  let source =
    #|public extension User {
    #|    /// Shouts.
    #|    func shout() -> String { return "" }
    #|}
    #|
    #|public func top() {}
  assert_true(typed_oop_parses_fully(registry, "swift", source))
  assert_eq(
    typed_oop_owner_of(registry, "swift", source, "E.swift", "shout"),
    "E.swift::User",
  )
  assert_eq(
    typed_oop_owner_of(registry, "swift", source, "E.swift", "top"),
    "E.swift",
  )
  let names = typed_oop_kinds(registry, "swift", source, "E.swift")
  assert_true(names.get("top") == Some("Function"))
}

///|
/// Root cause: a Java import names a package path from the root of the SOURCE
/// TREE, but the spec resolved it relative to the importing file's directory,
/// so a sibling package could never be found and every intra-project import
/// fell back to the `maven:` prefix — leaving the graph with no edge between
/// two files of the same project. Resolution is now anchored at
/// `<project root>/src/main/java`, found by walking up for the build manifest.
test "declares(typed_oop): java intra-project import resolves to the file" {
  let registry = get_fixture_registry()
  let source =
    #|package com.example.web;
    #|
    #|import java.util.Optional;
    #|import com.example.model.User;
  let existing = [
    "proj/pom.xml", "proj/src/main/java/com/example/model/User.java", "proj/src/main/java/com/example/web/C.java",
  ]
  let imports = typed_oop_imports_with_files(
    registry, "java", source, "proj/src/main/java/com/example/web/C.java", existing,
  )
  assert_eq(imports.length(), 2)
  // an import of a package that is not in this project keeps the fallback
  assert_eq(imports[0].0, "java.util.Optional")
  assert_eq(imports[0].1, "maven:java.util.Optional")
  // an import of a file in this project resolves to that file
  assert_eq(imports[1].0, "com.example.model.User")
  assert_eq(imports[1].1, "proj/src/main/java/com/example/model/User.java")
}

///|
/// Same for Kotlin, whose Gradle module may keep sources under either
/// `src/main/kotlin` or `src/main/java`; both are probed, Kotlin first.
test "declares(typed_oop): kotlin intra-project import resolves to the file" {
  let registry = get_fixture_registry()
  let source =
    #|package com.example
    #|
    #|import com.example.service.GreetingService
    #|import org.springframework.boot.runApplication
  let existing = [
    "proj/build.gradle.kts", "proj/src/main/kotlin/com/example/service/GreetingService.kt",
    "proj/src/main/kotlin/com/example/A.kt",
  ]
  let imports = typed_oop_imports_with_files(
    registry, "kotlin", source, "proj/src/main/kotlin/com/example/A.kt", existing,
  )
  assert_eq(imports.length(), 2)
  assert_eq(imports[0].0, "com.example.service.GreetingService")
  assert_eq(
    imports[0].1,
    "proj/src/main/kotlin/com/example/service/GreetingService.kt",
  )
  // an external dependency keeps the prefixed fallback
  assert_eq(imports[1].0, "org.springframework.boot.runApplication")
  assert_eq(imports[1].1, "maven:org.springframework.boot.runApplication")
}

///|
/// A project with no build manifest at all must not invent edges: with no
/// root to anchor against, every import simply keeps the prefixed fallback.
test "declares(typed_oop): imports fall back safely with no build manifest" {
  let registry = get_fixture_registry()
  let imports = typed_oop_imports_with_files(
    registry,
    "java",
    "import com.example.model.User;\n",
    "loose/C.java",
    ["loose/C.java"],
  )
  assert_eq(imports.length(), 1)
  assert_eq(imports[0].1, "maven:com.example.model.User")
}
