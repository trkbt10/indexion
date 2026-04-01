import { useState, useEffect, useCallback } from "react";
import { Outlet } from "react-router";
import { client, isStaticMode } from "../../lib/client.ts";
import { invalidateScope } from "../../lib/api-cache.ts";
import {
  checkHealth,
  fetchDigestStats,
  rebuildDigest,
} from "@indexion/api-client";
import { LoadingSpinner } from "./loading-spinner.tsx";
import { ConnectionErrorState } from "./connection-error-state.tsx";
import { OnboardingState } from "./onboarding-state.tsx";

type GuardStatus = "checking" | "no-connection" | "no-data" | "ready";

export const ConnectionGuard = (): React.JSX.Element => {
  const [status, setStatus] = useState<GuardStatus>(
    isStaticMode ? "ready" : "checking",
  );
  const [retrying, setRetrying] = useState(false);
  const [building, setBuilding] = useState(false);
  const [built, setBuilt] = useState(false);
  const [functionCount, setFunctionCount] = useState(0);

  const check = useCallback(async () => {
    if (isStaticMode) {
      return;
    }
    setStatus("checking");
    const health = await checkHealth(client);
    if (!health.ok) {
      setStatus("no-connection");
      return;
    }
    const stats = await fetchDigestStats<{ totalSymbols: number }>(client);
    if (!stats.ok || stats.data.totalSymbols === 0) {
      setStatus("no-data");
      return;
    }
    setStatus("ready");
  }, []);

  useEffect(() => {
    check();
  }, [check]);

  const handleRetry = useCallback(() => {
    setRetrying(true);
    check().finally(() => setRetrying(false));
  }, [check]);

  const handleBuild = useCallback(async () => {
    setBuilding(true);
    const result = await rebuildDigest(client);
    setBuilding(false);
    if (result.ok) {
      invalidateScope("digest");
      setBuilt(true);
      setFunctionCount(result.data.functions);
      // Brief delay to show success, then recheck
      setTimeout(() => {
        check();
      }, 1200);
    }
  }, [check]);

  switch (status) {
    case "checking":
      return <LoadingSpinner message="Connecting to server..." />;
    case "no-connection":
      return <ConnectionErrorState onRetry={handleRetry} retrying={retrying} />;
    case "no-data":
      return (
        <OnboardingState
          onBuild={handleBuild}
          building={building}
          built={built}
          functionCount={functionCount}
        />
      );
    case "ready":
      return <Outlet />;
  }
};
