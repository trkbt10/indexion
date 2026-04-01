import { WifiOff, RefreshCw } from "lucide-react";
import { Button } from "../ui/button.tsx";

type Props = {
  readonly onRetry: () => void;
  readonly retrying: boolean;
};

export const ConnectionErrorState = ({
  onRetry,
  retrying,
}: Props): React.JSX.Element => (
  <div className="flex h-full flex-col items-center justify-center gap-6 p-8">
    <div className="rounded-full bg-destructive/10 p-4">
      <WifiOff className="size-8 text-destructive" />
    </div>
    <div className="flex flex-col items-center gap-2 text-center">
      <h2 className="text-lg font-semibold">Cannot connect to server</h2>
      <p className="max-w-sm text-sm text-muted-foreground">
        Make sure{" "}
        <code className="rounded bg-muted px-1 py-0.5 text-xs">
          indexion serve
        </code>{" "}
        is running and accessible.
      </p>
    </div>
    <Button variant="outline" onClick={onRetry} disabled={retrying}>
      <RefreshCw className={`size-3.5 ${retrying ? "animate-spin" : ""}`} />
      Retry
    </Button>
  </div>
);
