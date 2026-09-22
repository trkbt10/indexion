/** Severity levels, ordered from least to most severe. */
export type Level = "debug" | "info" | "warn" | "error";

/**
 * A minimal structured logger.
 *
 * The storefront writes newline-delimited JSON so that the log shipper
 * can parse records without a grok pattern.
 */
export class Logger {
  constructor(private readonly scope: string) {}

  /** Emit a record at the given level. */
  log(level: Level, message: string, fields: Record<string, unknown> = {}): void {
    const record = { level, scope: this.scope, message, ...fields };
    console.log(JSON.stringify(record));
  }

  info(message: string, fields?: Record<string, unknown>): void {
    this.log("info", message, fields);
  }
}
