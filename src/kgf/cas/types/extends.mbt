// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend CASManifest with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend CASManifest with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend CASManifest with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend CASManifest with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend CASManifest with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ContentHash with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ContentHash with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ContentHash with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ContentHash with FromJson::{from_json}

///|
#deprecated("Use `Hash::hash` instead")
#doc(hidden)
pub extend ContentHash with Hash::{hash}

///|
#deprecated("Use `Hash::hash_combine` instead")
#doc(hidden)
pub extend ContentHash with Hash::{hash_combine}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend ContentHash with Show::{output}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ContentHash with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ModuleChunk with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ModuleChunk with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ModuleChunk with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ModuleChunk with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ModuleChunk with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend SymbolicRef with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend SymbolicRef with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend SymbolicRef with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend SymbolicRef with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend SymbolicRef with ToJson::{to_json}
