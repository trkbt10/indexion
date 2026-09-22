/**
 * Formatting helpers for the maintenance scripts.
 *
 * These run under plain Node with no build step, which is why the
 * directory carries a jsconfig.json rather than a tsconfig.json.
 */

/** Render minor units as a human-readable amount. */
export function formatMinorUnits(minorUnits, currency = "USD") {
  const major = (minorUnits / 100).toFixed(2);
  return `${major} ${currency}`;
}

/** Render a table of rows as aligned plain text. */
export function formatTable(rows) {
  return rows.map((row) => row.join("\t")).join("\n");
}
