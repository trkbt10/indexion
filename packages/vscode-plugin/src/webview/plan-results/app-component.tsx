/**
 * @file Plan results app component, extracted for testability.
 */

import React from "react";
import type { PlanResultsToWebview, PlanResultsFromWebview } from "../../panels/plan-results/messages.ts";
import { usePostMessage, useWebviewReducer } from "../bridge/context.tsx";
import styles from "./app.module.css";

// ─── State & reducer ────────────────────────────────────

type PlanResultsState = {
  readonly title: string;
  readonly content: string;
  readonly format: string;
} | null;

const planResultsReducer = (state: PlanResultsState, action: PlanResultsToWebview): PlanResultsState => {
  switch (action.type) {
    case "resultLoaded":
      return { title: action.title, content: action.content, format: action.format };
    default:
      return state;
  }
};

// ─── Component ──────────────────────────────────────────

export const PlanResultsApp = (): React.JSX.Element => {
  const postMessage = usePostMessage<PlanResultsFromWebview>();
  const [result] = useWebviewReducer(planResultsReducer, null);

  if (!result) {
    return <div className={styles.loading}>Loading results...</div>;
  }

  const handleCopy = (): void => {
    postMessage({ type: "copyContent" });
  };

  const handleFileClick = (filePath: string): void => {
    postMessage({ type: "openFile", filePath });
  };

  const renderContent = (): React.JSX.Element => {
    if (result.format === "json") {
      return <pre className={styles.codeBlock}>{result.content}</pre>;
    }

    const lines = result.content.split("\n");
    return (
      <div className={styles.markdown}>
        {lines.map((line, i) => {
          const fileMatch = /`([^`]+\.\w+)`/.exec(line);
          if (fileMatch) {
            const filePath = fileMatch[1];
            return (
              <div key={i} className={styles.line}>
                {line.split(fileMatch[0]).map((part, j) => (
                  <React.Fragment key={j}>
                    {j > 0 && (
                      <button className={styles.fileLink} onClick={() => handleFileClick(filePath)} type="button">
                        {filePath}
                      </button>
                    )}
                    {part}
                  </React.Fragment>
                ))}
              </div>
            );
          }
          return (
            <div key={i} className={styles.line}>
              {line}
            </div>
          );
        })}
      </div>
    );
  };

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1 className={styles.title}>{result.title}</h1>
        <button className={styles.copyButton} onClick={handleCopy} type="button">
          Copy
        </button>
      </div>
      {renderContent()}
    </div>
  );
};
