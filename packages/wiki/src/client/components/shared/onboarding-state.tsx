import { Database, RefreshCw, CheckCircle2 } from "lucide-react";
import { Button } from "../ui/button.tsx";

type Props = {
  readonly onBuild: () => void;
  readonly building: boolean;
  readonly built: boolean;
  readonly functionCount: number;
};

export const OnboardingState = ({
  onBuild,
  building,
  built,
  functionCount,
}: Props): React.JSX.Element => (
  <div className="flex h-full flex-col items-center justify-center gap-6 p-8">
    <div className="rounded-full bg-accent p-4">
      {built ? (
        <CheckCircle2 className="size-8 text-green-400" />
      ) : (
        <Database className="size-8 text-muted-foreground" />
      )}
    </div>
    <div className="flex flex-col items-center gap-2 text-center">
      <h2 className="text-lg font-semibold">
        {built ? "Index built successfully" : "Welcome to indexion"}
      </h2>
      <p className="max-w-md text-sm text-muted-foreground">
        {built
          ? `${functionCount} functions indexed. Reloading...`
          : "No index data found. Build the index to explore your codebase's structure, symbols, and dependencies."}
      </p>
    </div>
    {!built && (
      <Button onClick={onBuild} disabled={building}>
        <RefreshCw className={`size-3.5 ${building ? "animate-spin" : ""}`} />
        {building ? "Building index..." : "Build Index"}
      </Button>
    )}
  </div>
);
