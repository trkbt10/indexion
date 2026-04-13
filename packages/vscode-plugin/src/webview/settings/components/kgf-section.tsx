/**
 * @file KGF management section within the settings panel.
 */

import React, { useCallback, useEffect } from "react";
import { usePostMessage, useWebviewReducer } from "../../bridge/context.tsx";
import styles from "./kgf-section.module.css";

/** KGF spec entry received from the extension host. */
type KgfSpec = {
  readonly name: string;
  readonly category: string;
  readonly sources: ReadonlyArray<string>;
};

/** Messages specific to KGF management. */
type KgfFromWebview =
  | { readonly type: "kgfAdd"; readonly specName: string }
  | { readonly type: "kgfUpdate" }
  | { readonly type: "kgfLoadList" };

type KgfToWebview =
  | { readonly type: "kgfListLoaded"; readonly specs: ReadonlyArray<KgfSpec> }
  | { readonly type: "kgfActionDone"; readonly message: string };

// ─── State & reducer ────────────────────────────────────

type KgfState = {
  readonly specs: ReadonlyArray<KgfSpec>;
  readonly addInput: string;
  readonly status: string;
  /** Monotonic counter incremented on action done to trigger list reload + status auto-clear. */
  readonly actionVersion: number;
};

const initialState: KgfState = {
  specs: [],
  addInput: "",
  status: "",
  actionVersion: 0,
};

type KgfAction =
  | KgfToWebview
  | { readonly type: "setAddInput"; readonly value: string }
  | { readonly type: "clearAddInput" }
  | { readonly type: "setUpdating" }
  | { readonly type: "clearStatus" };

const kgfReducer = (state: KgfState, action: KgfAction): KgfState => {
  switch (action.type) {
    case "kgfListLoaded":
      return { ...state, specs: action.specs };
    case "kgfActionDone":
      return { ...state, status: action.message, actionVersion: state.actionVersion + 1 };
    case "setAddInput":
      return { ...state, addInput: action.value };
    case "clearAddInput":
      return { ...state, addInput: "" };
    case "setUpdating":
      return { ...state, status: "Updating..." };
    case "clearStatus":
      return { ...state, status: "" };
    default:
      return state;
  }
};

// ─── Component ──────────────────────────────────────────

export const KgfSection = (): React.JSX.Element => {
  const postMessage = usePostMessage<KgfFromWebview>();
  const [state, dispatch] = useWebviewReducer(kgfReducer, initialState);
  const { specs, addInput, status, actionVersion } = state;

  useEffect(() => {
    postMessage({ type: "kgfLoadList" });
  }, [postMessage]);

  // Reload list + auto-clear status after action completes
  useEffect(() => {
    if (actionVersion === 0) {
      return;
    }
    postMessage({ type: "kgfLoadList" });
    const timer = setTimeout(() => dispatch({ type: "clearStatus" }), 3000);
    return () => clearTimeout(timer);
  }, [actionVersion, postMessage, dispatch]);

  const handleAdd = useCallback((): void => {
    if (addInput.trim()) {
      postMessage({ type: "kgfAdd", specName: addInput.trim() });
      dispatch({ type: "clearAddInput" });
    }
  }, [addInput, postMessage, dispatch]);

  const handleUpdateAll = useCallback((): void => {
    postMessage({ type: "kgfUpdate" });
    dispatch({ type: "setUpdating" });
  }, [postMessage, dispatch]);

  const grouped = new Map<string, Array<KgfSpec>>();
  for (const spec of specs) {
    const category = spec.category || "other";
    const existing = grouped.get(category) ?? [];
    existing.push(spec);
    grouped.set(category, existing);
  }

  return (
    <div className={styles.section}>
      <h2 className={styles.heading}>KGF Specs</h2>

      {status && <div className={styles.status}>{status}</div>}

      <div className={styles.actions}>
        <div className={styles.addRow}>
          <input
            className={styles.input}
            type="text"
            value={addInput}
            placeholder="spec name (e.g., python)"
            onChange={(e) => dispatch({ type: "setAddInput", value: e.target.value })}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                handleAdd();
              }
            }}
          />
          <button className={styles.button} onClick={handleAdd} type="button">
            Add
          </button>
        </div>
        <button className={styles.buttonSecondary} onClick={handleUpdateAll} type="button">
          Update All
        </button>
      </div>

      <div className={styles.specList}>
        {[...grouped.entries()].map(([category, categorySpecs]) => (
          <div key={category} className={styles.category}>
            <div className={styles.categoryName}>{category}/</div>
            {categorySpecs.map((spec) => (
              <div key={spec.name} className={styles.specItem}>
                <span className={styles.specName}>{spec.name}</span>
                <span className={styles.specSources}>{spec.sources.join(", ")}</span>
              </div>
            ))}
          </div>
        ))}
        {specs.length === 0 && <div className={styles.empty}>No KGF specs installed</div>}
      </div>
    </div>
  );
};
