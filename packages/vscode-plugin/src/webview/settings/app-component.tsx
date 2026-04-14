/**
 * @file Settings app component, extracted for testability.
 */

import React, { useCallback, useEffect } from "react";
import type { SettingsToWebview, SettingsFromWebview, SettingsConfig } from "../../panels/settings/messages.ts";
import { usePostMessage, useWebviewReducer } from "../bridge/context.tsx";
import { ConfigSection } from "./components/config-section.tsx";
import styles from "./app.module.css";

const DEFAULT_CONFIG: SettingsConfig = {
  binaryPath: "",
  specsDir: "kgfs",
  defaultThreshold: 0.7,
  defaultStrategy: "hybrid",
  includes: [],
  excludes: [],
};

// ─── State & reducer ────────────────────────────────────

type SettingsState = {
  readonly globalConfig: SettingsConfig;
  readonly localConfig: SettingsConfig;
  readonly activeTab: "global" | "local";
  readonly saveStatus: string;
  /** Monotonic counter incremented on each save to trigger status auto-clear. */
  readonly saveVersion: number;
};

const initialState: SettingsState = {
  globalConfig: DEFAULT_CONFIG,
  localConfig: DEFAULT_CONFIG,
  activeTab: "local",
  saveStatus: "",
  saveVersion: 0,
};

type SettingsAction =
  | SettingsToWebview
  | { readonly type: "setActiveTab"; readonly tab: "global" | "local" }
  | { readonly type: "updateConfig"; readonly scope: "global" | "local"; readonly config: SettingsConfig }
  | { readonly type: "clearSaveStatus" };

const settingsReducer = (state: SettingsState, action: SettingsAction): SettingsState => {
  switch (action.type) {
    case "configLoaded":
      return { ...state, globalConfig: action.global, localConfig: action.local };
    case "saved":
      return {
        ...state,
        saveStatus: action.success ? "Saved!" : "Failed to save",
        saveVersion: state.saveVersion + 1,
      };
    case "setActiveTab":
      return { ...state, activeTab: action.tab };
    case "updateConfig":
      if (action.scope === "global") {
        return { ...state, globalConfig: action.config };
      }
      return { ...state, localConfig: action.config };
    case "clearSaveStatus":
      return { ...state, saveStatus: "" };
    default:
      return state;
  }
};

const TAB_SCOPES = ["local", "global"] as const;

// ─── Component ──────────────────────────────────────────

export const SettingsApp = (): React.JSX.Element => {
  const postMessage = usePostMessage<SettingsFromWebview>();
  const [state, dispatch] = useWebviewReducer(settingsReducer, initialState);
  const { globalConfig, localConfig, activeTab, saveStatus, saveVersion } = state;

  useEffect(() => {
    postMessage({ type: "load" });
  }, [postMessage]);

  useEffect(() => {
    if (saveVersion === 0) {
      return;
    }
    const timer = setTimeout(() => dispatch({ type: "clearSaveStatus" }), 2000);
    return () => clearTimeout(timer);
  }, [saveVersion, dispatch]);

  const handleSave = useCallback(
    (scope: "global" | "local", config: SettingsConfig): void => {
      postMessage({ type: "save", scope, config });
    },
    [postMessage],
  );

  const handleTabSelect = useCallback(
    (e: React.SyntheticEvent) => {
      const detail = (e.nativeEvent as CustomEvent<{ selectedIndex: number }>).detail;
      dispatch({ type: "setActiveTab", tab: TAB_SCOPES[detail.selectedIndex] });
    },
    [dispatch],
  );

  return (
    <div className={styles.container}>
      <h1 className={styles.title}>indexion Settings</h1>
      {saveStatus && <div className={styles.status}>{saveStatus}</div>}
      <vscode-tabs selected-index={activeTab === "local" ? 0 : 1} onVsc-tabs-select={handleTabSelect}>
        <vscode-tab-header slot="header">Local (.indexion/)</vscode-tab-header>
        <vscode-tab-header slot="header">Global</vscode-tab-header>
        <vscode-tab-panel>
          <ConfigSection
            config={localConfig}
            onChange={(config) => dispatch({ type: "updateConfig", scope: "local", config })}
            onSave={(config) => handleSave("local", config)}
          />
        </vscode-tab-panel>
        <vscode-tab-panel>
          <ConfigSection
            config={globalConfig}
            onChange={(config) => dispatch({ type: "updateConfig", scope: "global", config })}
            onSave={(config) => handleSave("global", config)}
          />
        </vscode-tab-panel>
      </vscode-tabs>
    </div>
  );
};
