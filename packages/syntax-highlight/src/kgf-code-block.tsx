/**
 * @file Code block with KGF-based syntax highlighting.
 *
 * Extracts language from className (e.g. "language-typescript"),
 * resolves the KGF spec name via LANG_ALIASES, and tokenizes + colors.
 *
 * Requires a KgfSpecProvider ancestor to fetch specs. Without one,
 * renders plain unhighlighted code.
 */

import { useMemo } from "react";
import { useKgfHighlight } from "./use-kgf-highlight.ts";

/** Map markdown language hints to KGF spec names. */
export const LANG_ALIASES: Record<string, string> = {
  ts: "typescript",
  tsx: "typescript-jsx",
  js: "javascript",
  jsx: "javascript-jsx",
  py: "python",
  rb: "ruby",
  rs: "rust",
  cs: "csharp",
  kt: "kotlin",
  sh: "bash",
  bash: "bash",
  yml: "yaml",
  mbt: "moonbit",
};

function resolveLang(className: string | undefined): string | null {
  const match = /language-(\S+)/.exec(className ?? "");
  if (!match) {
    return null;
  }
  const raw = match[1]!;
  return LANG_ALIASES[raw] ?? raw;
}

type Props = React.HTMLAttributes<HTMLElement> & {
  children?: React.ReactNode;
  className?: string;
};

export const KgfCodeBlock = (props: Props): React.JSX.Element => {
  const lang = useMemo(() => resolveLang(props.className), [props.className]);
  const code = String(props.children).replace(/\n$/, "");
  const { segments } = useKgfHighlight(lang, code);

  return (
    <code className={props.className}>
      {segments.map((seg, i) =>
        seg.color ? (
          <span key={i} style={{ color: seg.color }}>
            {seg.text}
          </span>
        ) : (
          <span key={i}>{seg.text}</span>
        ),
      )}
    </code>
  );
};
