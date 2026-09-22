// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend DigestManifest with ToJson::{to_json}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DigestManifest with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DigestManifest with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DigestManifest with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend DigestManifest with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend FileEntry with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend FileEntry with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend FileEntry with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend FileEntry with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend FileEntry with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend FunctionEntry with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend FunctionEntry with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend FunctionEntry with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend FunctionEntry with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend FunctionEntry with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ProviderMeta with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ProviderMeta with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ProviderMeta with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ProviderMeta with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ProviderMeta with ToJson::{to_json}
