import { AlertCircle } from "lucide-react";

export const ErrorPanel = ({
  message,
}: {
  readonly message: string;
}): React.JSX.Element => (
  <div className="flex items-start gap-3 rounded-lg border border-destructive/30 bg-destructive/10 p-4">
    <AlertCircle className="mt-0.5 size-4 shrink-0 text-destructive" />
    <div className="flex flex-col gap-1">
      <span className="text-xs font-semibold uppercase text-destructive">
        Error
      </span>
      <span className="break-words text-sm">{message}</span>
    </div>
  </div>
);
