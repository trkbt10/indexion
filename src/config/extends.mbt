// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend DocConfig with ToJson::{to_json}

///|
pub extend DocPackageEntry with ToJson::{to_json}

///|
pub extend DocRootConfig with ToJson::{to_json}

///|
pub extend DocRootSection with ToJson::{to_json}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DigestFileConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DigestFileConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DigestFileConfig with Eq::{equal}

///|
#deprecated("Use `Show::to_string` instead")
#doc(hidden)
pub extend DigestFileConfig with Show::{to_string}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend DigestFileConfig with Show::{output}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DocConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DocConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DocConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DocFileConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DocFileConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DocFileConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DocOutputConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DocOutputConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DocOutputConfig with Eq::{equal}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend DocOutputConfig with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DocPackageEntry with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DocPackageEntry with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DocPackageEntry with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DocRootConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DocRootConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DocRootConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DocRootSection with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DocRootSection with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DocRootSection with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend EffectiveReconcileConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend EffectiveReconcileConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend EffectiveReconcileConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend EmbeddingFileConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend EmbeddingFileConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend EmbeddingFileConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend GlobalConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend GlobalConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend GlobalConfig with Eq::{equal}

///|
#deprecated("Use `Show::to_string` instead")
#doc(hidden)
pub extend GlobalConfig with Show::{to_string}

///|
#deprecated("Use `Show::output` instead")
#doc(hidden)
pub extend GlobalConfig with Show::{output}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend McpFileConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend McpFileConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend McpFileConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ProjectFileConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ProjectFileConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ProjectFileConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ProviderFileEntry with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ProviderFileEntry with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ProviderFileEntry with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ReconcileDocumentScope with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ReconcileDocumentScope with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ReconcileDocumentScope with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ReconcileFileConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ReconcileFileConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ReconcileFileConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend WikiColorConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend WikiColorConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend WikiColorConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend WikiFileConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend WikiFileConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend WikiFileConfig with Eq::{equal}
