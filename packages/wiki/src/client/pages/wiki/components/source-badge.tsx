/**
 * @file Clickable source reference badge (e.g., "README.md 1-22").
 * Links to Browse page at the referenced file.
 */

import { Link } from "react-router";
import { FileCode } from "lucide-react";
import { Badge } from "../../../components/ui/badge.tsx";
import type { WikiSourceRef } from "@indexion/api-client";

type Props = {
  readonly source: WikiSourceRef;
};

export const SourceBadge = ({ source }: Props): React.JSX.Element => {
  const label =
    source.lines[1] > 0
      ? `${source.file} ${source.lines[0]}-${source.lines[1]}`
      : source.file;

  return (
    <Link to={`/?file=${encodeURIComponent(source.file)}`}>
      <Badge
        variant="outline"
        className="cursor-pointer gap-1 font-mono text-xs hover:bg-accent"
      >
        <FileCode className="size-3" />
        {label}
      </Badge>
    </Link>
  );
};
