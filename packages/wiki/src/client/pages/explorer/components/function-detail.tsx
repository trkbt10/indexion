import { X } from "lucide-react";
import { Button } from "../../../components/ui/button.tsx";
import { Badge } from "../../../components/ui/badge.tsx";
import { Separator } from "../../../components/ui/separator.tsx";
import type { IndexedFunction } from "@indexion/api-client";

type Props = {
  readonly fn: IndexedFunction;
  readonly onClose: () => void;
};

const Section = ({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) => (
  <div className="flex flex-col gap-1.5">
    <h3 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
      {label}
    </h3>
    {children}
  </div>
);

export const FunctionDetail = ({ fn, onClose }: Props): React.JSX.Element => (
  <div className="flex flex-col gap-4 p-4">
    <div className="flex items-start justify-between">
      <div className="flex flex-col gap-1">
        <code className="font-mono text-base font-semibold">{fn.name}</code>
        <span className="font-mono text-xs text-muted-foreground">
          {fn.module}
        </span>
      </div>
      <Button variant="ghost" size="icon" className="size-7" onClick={onClose}>
        <X className="size-4" />
      </Button>
    </div>

    <div className="flex gap-2">
      <Badge variant="secondary">{fn.kind}</Badge>
      <Badge variant="outline">depth {fn.depth}</Badge>
    </div>

    {fn.summary && (
      <>
        <Separator />
        <Section label="Summary">
          <p className="text-sm leading-relaxed">{fn.summary}</p>
        </Section>
      </>
    )}

    {fn.doc && (
      <Section label="Documentation">
        <p className="whitespace-pre-wrap text-sm text-muted-foreground">
          {fn.doc}
        </p>
      </Section>
    )}

    {fn.keywords.length > 0 && (
      <Section label="Keywords">
        <div className="flex flex-wrap gap-1.5">
          {fn.keywords.map((kw) => (
            <Badge key={kw} variant="outline" className="font-mono">
              {kw}
            </Badge>
          ))}
        </div>
      </Section>
    )}

    {fn.callers.length > 0 && (
      <Section label={`Called by (${fn.callers.length})`}>
        <div className="flex flex-col gap-1">
          {fn.callers.map((c) => (
            <code
              key={c}
              className="rounded-md bg-muted px-2 py-1 font-mono text-xs"
            >
              {c}
            </code>
          ))}
        </div>
      </Section>
    )}

    {fn.callees.length > 0 && (
      <Section label={`Calls (${fn.callees.length})`}>
        <div className="flex flex-col gap-1">
          {fn.callees.map((c) => (
            <code
              key={c}
              className="rounded-md bg-muted px-2 py-1 font-mono text-xs"
            >
              {c}
            </code>
          ))}
        </div>
      </Section>
    )}
  </div>
);
