/**
 * Format a class name string.
 */
export function formatClassName(base: string, variant: string): string {
  return `${base}-${variant}`;
}

/**
 * Validate that a value is non-empty.
 */
export function isNonEmpty(value: string): boolean {
  return value.trim().length > 0;
}
