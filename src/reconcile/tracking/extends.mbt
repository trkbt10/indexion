// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend FileState with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend FileState with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend FileState with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend FileState with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend FileState with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend FileTrackingConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend FileTrackingConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend FileTrackingConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend TimestampInfo with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend TimestampInfo with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend TimestampInfo with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend TimestampInfo with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend TimestampInfo with ToJson::{to_json}
