/**
 * @file Right sidebar: page table of contents.
 */

import { ScrollArea } from "../../../components/ui/scroll-area.tsx";
import { cn } from "../../../lib/utils.ts";
import type { WikiHeading } from "@indexion/api-client";

type Props = {
  readonly headings: ReadonlyArray<WikiHeading>;
};

export const WikiToc = ({ headings }: Props): React.JSX.Element | null => {
  if (headings.length === 0) return null;

  return (
    <ScrollArea className="h-full border-l">
      <div className="p-4">
        <h3 className="mb-3 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          On this page
        </h3>
        <nav className="space-y-1">
          {headings.map((h, i) => (
            <a
              key={`${i}-${h.anchor}`}
              href={`#${h.anchor}`}
              className={cn(
                "block text-sm leading-snug text-muted-foreground transition-colors hover:text-foreground",
                h.level === 2 && "pl-0",
                h.level === 3 && "pl-3",
                h.level === 4 && "pl-6",
              )}
            >
              {h.text}
            </a>
          ))}
        </nav>
      </div>
    </ScrollArea>
  );
};
