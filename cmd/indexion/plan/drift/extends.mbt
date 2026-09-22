// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend DriftReport with ToJson::{to_json}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DriftDirection with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DriftDirection with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DriftDirection with Eq::{equal}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend DriftDirection with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DriftGapTerm with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DriftGapTerm with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DriftGapTerm with Eq::{equal}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend DriftGapTerm with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DriftReport with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DriftReport with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DriftReport with Eq::{equal}
