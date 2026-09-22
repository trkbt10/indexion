// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend ReconcileReport with ToJson::{to_json}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ActReconcileCandidate with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DriftAction with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DriftAction with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DriftAction with Eq::{equal}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend DriftAction with ToJson::{to_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ImplMatch with ToJson::{to_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend PlotAct with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ReconcileFormat with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ReconcileFormat with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ReconcileFormat with Eq::{equal}
