// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend EmbeddingApiConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend EmbeddingApiConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend EmbeddingApiConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend EmbeddingProvider with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend EmbeddingProvider with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend EmbeddingProvider with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend EmbeddingSource with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend EmbeddingSource with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend EmbeddingSource with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ProviderConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ProviderConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ProviderConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend VcdbStrategy with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend VcdbStrategy with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend VcdbStrategy with Eq::{equal}
