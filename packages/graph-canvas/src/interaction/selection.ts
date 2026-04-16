/**
 * @file Immutable selection and focus-mode updates for React state.
 */

import type { SelectionState, ViewEdge } from "../types.ts";

export function createSelectionState(): SelectionState {
  return {
    selected: new Set(),
    focusCenter: null,
    focusNeighbors: new Set(),
  };
}

export function toggleSelect(
  state: SelectionState,
  nodeId: string,
  shift: boolean,
): SelectionState {
  const selected = shift ? new Set(state.selected) : new Set<string>();
  if (selected.has(nodeId)) {
    selected.delete(nodeId);
  } else {
    selected.add(nodeId);
  }
  return {
    selected,
    focusCenter: state.focusCenter,
    focusNeighbors: new Set(state.focusNeighbors),
  };
}

export function clearSelection(state: SelectionState): SelectionState {
  if (state.selected.size === 0) return state;
  return {
    selected: new Set(),
    focusCenter: state.focusCenter,
    focusNeighbors: new Set(state.focusNeighbors),
  };
}

export function enterFocusMode(
  state: SelectionState,
  nodeId: string,
  edges: readonly ViewEdge[],
): SelectionState {
  const focusNeighbors = new Set<string>([nodeId]);
  for (const edge of edges) {
    if (edge.sourceId === nodeId) {
      focusNeighbors.add(edge.targetId);
    }
    if (edge.targetId === nodeId) {
      focusNeighbors.add(edge.sourceId);
    }
  }
  return {
    selected: new Set(state.selected),
    focusCenter: nodeId,
    focusNeighbors,
  };
}

export function exitFocusMode(state: SelectionState): SelectionState {
  if (!state.focusCenter && state.focusNeighbors.size === 0) return state;
  return {
    selected: new Set(state.selected),
    focusCenter: null,
    focusNeighbors: new Set(),
  };
}
