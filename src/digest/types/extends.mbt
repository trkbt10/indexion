// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend EmbeddingConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend EmbeddingConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend EmbeddingConfig with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend EmbeddingConfig with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend EmbeddingConfig with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend FunctionEmbedding with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend FunctionEmbedding with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend FunctionEmbedding with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend FunctionHash with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend FunctionHash with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend FunctionHash with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend FunctionHash with FromJson::{from_json}

///|
#deprecated("Use `Hash::hash` instead")
#doc(hidden)
pub extend FunctionHash with Hash::{hash}

///|
#deprecated("Use `Hash::hash_combine` instead")
#doc(hidden)
pub extend FunctionHash with Hash::{hash_combine}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend FunctionHash with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend FunctionUnit with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend FunctionUnit with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend FunctionUnit with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend FunctionUnit with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend FunctionUnit with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend Impression with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend Impression with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend Impression with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend Impression with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend Impression with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend QueryHit with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend QueryHit with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend QueryHit with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend QueryOptions with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend QueryOptions with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend QueryOptions with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend RemoteEmbeddingConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend RemoteEmbeddingConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend RemoteEmbeddingConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend RemoteEmbeddingProvider with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend RemoteEmbeddingProvider with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend RemoteEmbeddingProvider with Eq::{equal}
