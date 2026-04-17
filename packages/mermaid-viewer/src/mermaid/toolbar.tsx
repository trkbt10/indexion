/**
 * @file Overlay toolbar primitives shared by the inline and full-screen viewers.
 *
 * `ToolButton` stops pointer/click propagation so clicks don't get absorbed
 * by the zoom-pan-pinch pan handler underneath.
 */

const Toolbar = ({
  position,
  size,
  children,
}: {
  readonly position: string;
  readonly size: string;
  readonly children: React.ReactNode;
}): React.JSX.Element => (
  <div className={`absolute ${position} z-10 flex gap-1 [&_svg]:${size}`}>
    {children}
  </div>
);

const ToolButton = ({
  onClick,
  label,
  children,
}: {
  readonly onClick: () => void;
  readonly label: string;
  readonly children: React.ReactNode;
}): React.JSX.Element => (
  <button
    type="button"
    onPointerDown={(e) => e.stopPropagation()}
    onClick={(e) => {
      e.stopPropagation();
      onClick();
    }}
    aria-label={label}
    className="pointer-events-auto rounded bg-background/80 p-1 text-muted-foreground backdrop-blur-sm transition-colors hover:bg-accent hover:text-foreground"
  >
    {children}
  </button>
);

export { Toolbar, ToolButton };
