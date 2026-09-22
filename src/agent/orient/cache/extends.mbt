// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend Metadata with ToJson::{to_json}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend CachedFile with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend CachedFile with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend InvalidReason with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend InvalidReason with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend InvalidReason with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend Layout with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend Layout with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend Layout with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend Metadata with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend Metadata with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend Metadata with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend Metadata with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend MetadataRead with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend MetadataRead with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend MetadataRead with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend OpenDecision with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend OpenDecision with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend OpenDecision with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend OpenMode with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend OpenMode with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend OpenMode with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend RuntimeReadiness with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend RuntimeReadiness with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend RuntimeReadiness with Eq::{equal}
