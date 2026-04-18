/**
 * @file Selection reducer — the single source of truth for what the
 * viewport's selection and focus state are.
 *
 * All pointer and keyboard paths funnel through `applySelectionIntent`.
 * The reducer is pure: it takes an `SelectionIntent` and the current
 * state, returns the next state plus a `SelectionEffect` that the
 * host interprets (fit-to-view, focus-on-node, or nothing). No
 * side-effectful renderer calls happen inside the reducer — that's
 * why the same transitions play out identically in tests and in the
 * browser, and why bugs like "dbl-click-to-exit-focus sometimes
 * leaves focus active" can't reappear: a single branch decides both
 * the state and the effect for every possible input.
 */

import type {
  SelectionEffect,
  SelectionIntent,
  SelectionState,
  ViewEdge,
} from "../types.ts";

export function createSelectionState(): SelectionState {
  return {
    selected: new Set(),
    focusCenter: null,
    focusNeighbors: new Set(),
  };
}

export type SelectionTransition = {
  readonly state: SelectionState;
  readonly effect: SelectionEffect;
};

/** Reduce a user intent against the current selection state.
 *
 *  Rules (pinned down here so the behaviour is obvious from one
 *  place, not scattered across event handlers):
 *
 *    click on node, no shift  → select that one node only
 *    click on node, shift     → toggle that node's membership
 *    click on empty space     → clear selection (unless shift)
 *    dbl-click on a node that is NOT the current focus centre
 *                             → enter focus mode on it + focus-on-node
 *    dbl-click on the focus-centred node itself
 *                             → exit focus mode + fit-to-view
 *    dbl-click on empty       → exit focus if any + fit-to-view
 *    clear (keyboard esc etc.) → reset to empty state
 *
 *  Every transition is idempotent when the state wouldn't change —
 *  we return the same object reference so React's reference-identity
 *  checks skip redundant re-renders.
 */
export function applySelectionIntent(args: {
  readonly state: SelectionState;
  readonly intent: SelectionIntent;
  readonly edges: readonly ViewEdge[];
}): SelectionTransition {
  const { state, intent, edges } = args;
  switch (intent.type) {
    case "click": {
      const { node, shift } = intent;
      if (!node) {
        if (shift) {
          return { state, effect: { type: "none" } };
        }
        return {
          state: state.selected.size === 0 ? state : emptySelected(state),
          effect: { type: "none" },
        };
      }
      return {
        state: toggleMember(state, node.id, shift),
        effect: { type: "none" },
      };
    }
    case "double-click": {
      const node = intent.node;
      if (!node) {
        if (!state.focusCenter && state.selected.size === 0) {
          return { state, effect: { type: "fit-to-view" } };
        }
        return {
          state: resetAll(state),
          effect: { type: "fit-to-view" },
        };
      }
      if (state.focusCenter === node.id) {
        return {
          state: exitFocusKeepSelected(state),
          effect: { type: "fit-to-view" },
        };
      }
      return {
        state: enterFocus(state, node.id, edges),
        effect: { type: "focus-on-node", nodeId: node.id },
      };
    }
    case "clear":
      if (state.selected.size === 0 && !state.focusCenter) {
        return { state, effect: { type: "none" } };
      }
      return { state: resetAll(state), effect: { type: "none" } };
  }
}

// ─── Pure state mutators ─────────────────────────────────────────

function toggleMember(
  state: SelectionState,
  nodeId: string,
  shift: boolean,
): SelectionState {
  if (!shift) {
    if (state.selected.size === 1 && state.selected.has(nodeId)) {
      return state;
    }
    return {
      selected: new Set([nodeId]),
      focusCenter: state.focusCenter,
      focusNeighbors: state.focusNeighbors,
    };
  }
  const next = new Set(state.selected);
  if (next.has(nodeId)) {
    next.delete(nodeId);
  } else {
    next.add(nodeId);
  }
  return {
    selected: next,
    focusCenter: state.focusCenter,
    focusNeighbors: state.focusNeighbors,
  };
}

function emptySelected(state: SelectionState): SelectionState {
  return {
    selected: new Set(),
    focusCenter: state.focusCenter,
    focusNeighbors: state.focusNeighbors,
  };
}

function enterFocus(
  state: SelectionState,
  nodeId: string,
  edges: readonly ViewEdge[],
): SelectionState {
  const neighbours = new Set<string>([nodeId]);
  for (const edge of edges) {
    const other = otherEndpoint(edge, nodeId);
    if (other !== null) {
      neighbours.add(other);
    }
  }
  return {
    selected: new Set(state.selected),
    focusCenter: nodeId,
    focusNeighbors: neighbours,
  };
}

function exitFocusKeepSelected(state: SelectionState): SelectionState {
  return {
    selected: new Set(state.selected),
    focusCenter: null,
    focusNeighbors: new Set(),
  };
}

function resetAll(_state: SelectionState): SelectionState {
  return {
    selected: new Set(),
    focusCenter: null,
    focusNeighbors: new Set(),
  };
}

/** Return the endpoint of `edge` that is *not* `nodeId`, or null if
 *  `nodeId` is not a participant. */
function otherEndpoint(edge: ViewEdge, nodeId: string): string | null {
  if (edge.sourceId === nodeId) {
    return edge.targetId;
  }
  if (edge.targetId === nodeId) {
    return edge.sourceId;
  }
  return null;
}
