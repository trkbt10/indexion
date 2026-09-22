// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend ManifestPage with ToJson::{to_json}

///|
pub extend WikiManifest with ToJson::{to_json}

///|
pub extend WikiNav with ToJson::{to_json}

///|
pub extend WikiPage with ToJson::{to_json}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ManifestPage with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ManifestPage with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ManifestPage with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ManifestPage with FromJson::{from_json}

///|
#deprecated("Use `Show::to_string` instead")
#doc(hidden)
pub extend ManifestPage with Show::{to_string}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend ManifestPage with Show::{output}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend WikiHeading with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend WikiManifest with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend WikiManifest with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend WikiManifest with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend WikiManifest with FromJson::{from_json}

///|
#deprecated("Use `Show::to_string` instead")
#doc(hidden)
pub extend WikiManifest with Show::{to_string}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend WikiManifest with Show::{output}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend WikiNavItem with ToJson::{to_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend WikiSourceRef with ToJson::{to_json}
