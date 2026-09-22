// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend CodeGraph with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend CodeGraph with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend CodeGraph with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend CodeGraph with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend CodeGraph with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend Edge with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend Edge with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend Edge with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend Edge with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend Edge with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend EdgeKind with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend EdgeKind with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend EdgeKind with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend EdgeKind with FromJson::{from_json}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend EdgeKind with Show::{output}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend EdgeKind with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ModuleNode with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ModuleNode with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ModuleNode with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ModuleNode with FromJson::{from_json}

///|
#deprecated("Use `Show::to_string` instead")
#doc(hidden)
pub extend ModuleNode with Show::{to_string}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend ModuleNode with Show::{output}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ModuleNode with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ModuleNote with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ModuleNote with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ModuleNote with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ModuleNote with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ModuleNote with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend SymbolNode with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend SymbolNode with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend SymbolNode with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend SymbolNode with FromJson::{from_json}

///|
#deprecated("Use `Show::to_string` instead")
#doc(hidden)
pub extend SymbolNode with Show::{to_string}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend SymbolNode with Show::{output}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend SymbolNode with ToJson::{to_json}
