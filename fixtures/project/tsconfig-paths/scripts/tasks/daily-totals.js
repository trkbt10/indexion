import { formatMinorUnits, formatTable } from "~/report";

/**
 * Print yesterday's order totals.
 *
 * The task is intentionally dependency-free so it can be run straight
 * from a cron entry without installing anything.
 */
export function run(orders) {
  const rows = orders.map((order) => [
    order.id,
    formatMinorUnits(order.totalMinorUnits),
  ]);
  console.log(formatTable(rows));
  return rows.length;
}
