import { useEffect, useRef, useState } from "react";

type Props = {
  readonly code: string;
  readonly className?: string;
};

/**
 * Renders a mermaid diagram from source code string.
 * Lazy-loads the mermaid library on first use.
 */
export const MermaidDiagram = ({
  code,
  className,
}: Props): React.JSX.Element => {
  const containerRef = useRef<HTMLDivElement>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!code.trim() || !containerRef.current) {
      return;
    }
    let cancelled = false;
    setError(null);

    import("mermaid").then(({ default: mermaid }) => {
      if (cancelled) {
        return;
      }
      mermaid.initialize({ startOnLoad: false, theme: "dark" });
      const id = `mermaid-${Math.random().toString(36).slice(2)}`;
      mermaid
        .render(id, code)
        .then(({ svg }) => {
          if (!cancelled && containerRef.current) {
            containerRef.current.innerHTML = svg;
            // Make SVG responsive: fill container width, preserve aspect ratio
            const svgEl = containerRef.current.querySelector("svg");
            if (svgEl) {
              svgEl.style.maxWidth = "100%";
              svgEl.style.height = "auto";
            }
          }
        })
        .catch((err) => {
          if (!cancelled) {
            setError(String(err));
          }
        });
    });

    return () => {
      cancelled = true;
    };
  }, [code]);

  if (error) {
    return (
      <pre className="overflow-auto rounded border border-destructive/30 bg-destructive/10 p-3 text-xs text-destructive">
        {error}
      </pre>
    );
  }

  return <div ref={containerRef} className={className} />;
};
