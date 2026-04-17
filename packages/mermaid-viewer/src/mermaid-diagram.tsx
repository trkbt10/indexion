/**
 * @file Mermaid diagram renderer with pinch-to-zoom and pan support.
 *
 * The SVG keeps its intrinsic viewBox dimensions; TransformWrapper scales
 * it to fit the container width via setTransform(). Container height is
 * derived from the SVG aspect ratio against the measured width. The
 * diagram stays hidden until the initial fit completes to avoid a flash
 * at native scale.
 *
 * Implementation is split across ./mermaid/:
 *   - svg-parser       : raw SVG → normalized SvgData
 *   - mermaid-store    : dynamic import + per-source render cache
 *   - use-fit-to-width : width measurement and transform driving
 *   - toolbar          : shared overlay buttons
 *   - full-screen-viewer: expanded modal viewer
 */

import { useState } from "react";
import { TransformWrapper, TransformComponent } from "react-zoom-pan-pinch";
import { Fullscreen, Maximize2, ZoomIn, ZoomOut } from "lucide-react";
import { useMermaidSvg } from "./mermaid/mermaid-store.ts";
import { useFitToWidth } from "./mermaid/use-fit-to-width.ts";
import { Toolbar, ToolButton } from "./mermaid/toolbar.tsx";
import { FullScreenViewer } from "./mermaid/full-screen-viewer.tsx";

type Props = {
  readonly code: string;
  readonly className?: string;
};

export const MermaidDiagram = ({
  code,
  className,
}: Props): React.JSX.Element => {
  const { svg, error } = useMermaidSvg(code);
  const [expanded, setExpanded] = useState(false);
  const { outerRef, transformRef, displayHeight, fitToWidth, ready } =
    useFitToWidth(svg);

  if (error) {
    return (
      <pre className="overflow-auto rounded border border-destructive/30 bg-destructive/10 p-3 text-xs text-destructive">
        {error}
      </pre>
    );
  }

  if (!svg) {
    return (
      <div
        className={`flex h-32 items-center justify-center rounded border border-border/50 text-sm text-muted-foreground ${className ?? ""}`}
      >
        Loading diagram…
      </div>
    );
  }

  return (
    <>
      <div
        ref={outerRef}
        className={`relative overflow-hidden rounded border border-border/50 ${ready ? "visible" : "invisible"} ${className ?? ""}`}
        style={{ height: displayHeight }}
      >
        <TransformWrapper
          ref={transformRef}
          initialScale={1}
          minScale={0.1}
          maxScale={8}
          wheel={{ step: 0.1 }}
          panning={{ velocityDisabled: true }}
          limitToBounds={false}
        >
          {({ zoomIn, zoomOut }) => (
            <>
              <TransformComponent
                wrapperStyle={{ width: "100%", height: "100%" }}
              >
                <div dangerouslySetInnerHTML={{ __html: svg.html }} />
              </TransformComponent>
              <Toolbar position="right-1.5 top-1.5" size="size-3">
                <ToolButton onClick={() => zoomIn()} label="Zoom in">
                  <ZoomIn />
                </ToolButton>
                <ToolButton onClick={() => zoomOut()} label="Zoom out">
                  <ZoomOut />
                </ToolButton>
                <ToolButton onClick={fitToWidth} label="Fit width">
                  <Maximize2 />
                </ToolButton>
                <ToolButton
                  onClick={() => setExpanded(true)}
                  label="Full screen"
                >
                  <Fullscreen />
                </ToolButton>
              </Toolbar>
            </>
          )}
        </TransformWrapper>
      </div>

      {expanded && (
        <FullScreenViewer
          svgHtml={svg.html}
          onClose={() => setExpanded(false)}
        />
      )}
    </>
  );
};
