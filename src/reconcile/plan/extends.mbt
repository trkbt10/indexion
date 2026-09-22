// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend ReconcileManifest with ToJson::{to_json}

///|
pub extend ReconcileReport with ToJson::{to_json}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend CacheState with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend CacheState with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend CacheState with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend CacheState with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend CacheState with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend CodeAnchor with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend CodeAnchor with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend CodeAnchor with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend CodeAnchor with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend CodeAnchor with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend CodeUnit with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend CodeUnit with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend CodeUnit with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend CodeUnit with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend CodeUnit with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DocAnchor with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DocAnchor with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DocAnchor with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend DocAnchor with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend DocAnchor with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend DocFragment with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend DocFragment with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend DocFragment with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend DocFragment with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend DocFragment with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend IndexedRecordEntry with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend IndexedRecordEntry with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend IndexedRecordEntry with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend IndexedRecordEntry with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend IndexedRecordEntry with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend LogicalReviewEntry with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend LogicalReviewEntry with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend LogicalReviewEntry with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend LogicalReviewEntry with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend LogicalReviewEntry with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend LogicalReviewTask with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend LogicalReviewTask with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend LogicalReviewTask with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend LogicalReviewTask with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend LogicalReviewTask with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend MappingEvidence with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend MappingEvidence with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend MappingEvidence with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend MappingEvidence with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend MappingEvidence with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ReconcileAggregateSuggestion with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ReconcileAggregateSuggestion with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ReconcileAggregateSuggestion with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ReconcileAggregateSuggestion with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ReconcileAggregateSuggestion with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ReconcileCandidate with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ReconcileCandidate with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ReconcileCandidate with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ReconcileCandidate with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ReconcileCandidate with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ReconcileConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ReconcileConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ReconcileConfig with Eq::{equal}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ReconcileManifest with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ReconcileManifest with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ReconcileManifest with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ReconcileManifest with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ReconcileReport with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ReconcileReport with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ReconcileReport with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ReconcileReport with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ReconcileReportConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ReconcileReportConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ReconcileReportConfig with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ReconcileReportConfig with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ReconcileReportConfig with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ReconcileSummary with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ReconcileSummary with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ReconcileSummary with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ReconcileSummary with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ReconcileSummary with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ReviewDecisionInput with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ReviewDecisionInput with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ReviewDecisionInput with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ReviewDecisionInput with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend VocabularyDivergence with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend VocabularyDivergence with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend VocabularyDivergence with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend VocabularyDivergence with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend VocabularyDivergence with ToJson::{to_json}
