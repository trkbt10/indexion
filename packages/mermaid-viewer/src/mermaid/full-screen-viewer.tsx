/**
 * @file Full-screen mermaid viewer overlay.
 *
 * Uses zoomToElement on mount (via ref callback + rAF) so the diagram is
 * auto-fitted to the viewport instead of being rendered at native scale.
 */

import { TransformWrapper, TransformComponent } from "react-zoom-pan-pinch";
import { Maximize2, X, ZoomIn, ZoomOut } from "lucide-react";
import { Toolbar, ToolButton } from "./toolbar.tsx";

export const FullScreenViewer = ({
  svgHtml,
  onClose,
}: {
  readonly svgHtml: string;
  readonly onClose: () => void;
}): React.JSX.Element => (
  <div className="fixed inset-0 z-50 bg-background">
    <TransformWrapper
      initialScale={1}
      minScale={0.3}
      maxScale={8}
      centerOnInit
      wheel={{ step: 0.1 }}
      panning={{ velocityDisabled: true }}
    >
      {({ zoomIn, zoomOut, resetTransform, zoomToElement }) => (
        <>
          <TransformComponent wrapperStyle={{ width: "100%", height: "100%" }}>
            <div
              ref={(el) => {
                if (el) {
                  requestAnimationFrame(() =>
                    zoomToElement(el, undefined, 100),
                  );
                }
              }}
              dangerouslySetInnerHTML={{ __html: svgHtml }}
            />
          </TransformComponent>
          <Toolbar position="right-3 top-3" size="size-3.5">
            <ToolButton onClick={() => zoomIn()} label="Zoom in">
              <ZoomIn />
            </ToolButton>
            <ToolButton onClick={() => zoomOut()} label="Zoom out">
              <ZoomOut />
            </ToolButton>
            <ToolButton onClick={() => resetTransform()} label="Reset">
              <Maximize2 />
            </ToolButton>
            <ToolButton onClick={onClose} label="Close">
              <X />
            </ToolButton>
          </Toolbar>
        </>
      )}
    </TransformWrapper>
  </div>
);
