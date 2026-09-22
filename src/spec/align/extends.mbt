// Explicit method promotion for trait impls (MoonBit warning 79,
// `implicit_impl_as_method`). Methods under "promoted" are called with dot
// syntax somewhere in this project; the rest are kept only as deprecated shims
// for the old implicit promotion and can be removed once it is gone.

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend AlignCacheManifest with ToJson::{to_json}

///|
pub extend AlignDiffReport with ToJson::{to_json}

///|
pub extend AlignDiffStore with ToJson::{to_json}

///|
pub extend AlignHistoryStore with ToJson::{to_json}

///|
pub extend AlignStatusReport with ToJson::{to_json}

///|
pub extend AlignSuggestReport with ToJson::{to_json}

///|
pub extend AlignTraceReport with ToJson::{to_json}

///|
pub extend AlignTraceStore with ToJson::{to_json}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignCacheManifest with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignCacheManifest with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignCacheManifest with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignCacheManifest with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignCommitInfo with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignCommitInfo with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignCommitInfo with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignCommitInfo with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend AlignCommitInfo with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignDiffItem with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignDiffItem with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignDiffItem with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignDiffItem with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend AlignDiffItem with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignDiffReport with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignDiffReport with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignDiffReport with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignDiffReport with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignDiffStore with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignDiffStore with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignDiffStore with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignDiffStore with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignHistoryEntry with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignHistoryEntry with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignHistoryEntry with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignHistoryEntry with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend AlignHistoryEntry with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignHistoryStore with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignHistoryStore with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignHistoryStore with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignHistoryStore with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignSnapshot with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignSnapshot with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignSnapshot with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignSnapshot with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend AlignSnapshot with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignStatusReport with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignStatusReport with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignStatusReport with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignStatusReport with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignSuggestReport with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignSuggestReport with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignSuggestReport with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignSuggestReport with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignSuggestion with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignSuggestion with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignSuggestion with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignSuggestion with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend AlignSuggestion with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignSummary with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignSummary with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignSummary with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignSummary with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend AlignSummary with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignTraceReport with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignTraceReport with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignTraceReport with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignTraceReport with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend AlignTraceStore with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend AlignTraceStore with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend AlignTraceStore with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend AlignTraceStore with FromJson::{from_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ImplementationNode with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ImplementationNode with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ImplementationNode with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ImplementationNode with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ImplementationNode with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend RequirementNode with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend RequirementNode with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend RequirementNode with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend RequirementNode with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend RequirementNode with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend ScenarioNode with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend ScenarioNode with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend ScenarioNode with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend ScenarioNode with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend ScenarioNode with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend SpecAlignConfig with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend SpecAlignConfig with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend SpecAlignConfig with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend SpecAlignConfig with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend SpecAlignConfig with ToJson::{to_json}

///|
#deprecated("Use `Repr(x)` instead")
#doc(hidden)
pub extend TraceEdge with Debug::{to_repr}

///|
#deprecated("Use `!=` instead")
#doc(hidden)
pub extend TraceEdge with Eq::{not_equal}

///|
#deprecated("Use `==` instead")
#doc(hidden)
pub extend TraceEdge with Eq::{equal}

///|
#deprecated("Use `FromJson::from_json` instead")
#doc(hidden)
pub extend TraceEdge with FromJson::{from_json}

///|
#deprecated("Use `ToJson::to_json` instead")
#doc(hidden)
pub extend TraceEdge with ToJson::{to_json}
